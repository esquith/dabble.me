# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/ClassLength
# rubocop:disable Metrics/PerceivedComplexity
# rubocop:disable Metrics/CyclomaticComplexity
require 'fileutils'

# Handle Emailed Entries
class EmailProcessor
  def initialize(email)
    @token = pick_meaningful_recipient(email.to, email.cc)
    @from = email.from[:email].downcase
    @to = email.to
    @cc = email.cc
    @bcc = email.bcc
    @subject = to_utf8(email.subject)
    @stripped_html = email.vendor_specific.try(:[], :stripped_html)
    @body = clean_message(email.body)
    @html = clean_html_version(@stripped_html)

    @raw_body = to_utf8(email.raw_body)
    @attachments = email.attachments
    @user = find_user_from_user_key(@token, @from)

    @inbound_email_params = {
      subject:     to_utf8(email.subject),
      cc:          email.cc,
      bcc:         email.bcc,
      spam_report: email.spam_report,
      headers:     email.headers,
      charsets:    email.charsets,
      stripped_html: @stripped_html
    }
  end

  def process
    if @user.present?
      Sentry.set_user(id: @user.id, email: @user.email)

      best_attachment = nil
      if @user.is_pro? && @attachments.present?
        @attachments.each do |attachment|
          next unless attachment.present?

          # Make sure attachments are at least 8kb so we're not saving a bunch of signuture/footer images
          file_size = File.size?(attachment.tempfile).to_i
          if (attachment.content_type == "application/octet-stream" || attachment.content_type =~ /^image\/(png|jpe?g|gif|heic|heif)$/i || attachment.original_filename =~ /^.+\.(heic|HEIC|Heic|heif|HEIF|Heif)$/i) && (file_size <= 0 || file_size > 8000) && file_size > 20000 && !attachment.original_filename.in?(["tmiFinal.png"])
            best_attachment = attachment
            break
          end
        end
      end

      # If image came in as a URL, try saving that
      best_attachment_url = nil
      if best_attachment.blank? && @stripped_html.present?
        email_reply_html = @stripped_html&.split(/reply to this email with your /i)&.first
        image_urls = email_reply_html&.scan(/<img\s.*?src=(?:'|")([^'">]+)(?:'|")/i)
        image_urls.flatten! if image_urls.present?
        if @user.is_pro? && image_urls.present? && image_urls.any?
          image_urls.each do |image_url|
            image_type = FastImage.type(image_url)

            if image_type.in?([:gif, :jpeg, :png])
              image_width, image_height = FastImage.size(image_url)
              next if image_height && image_width && image_height < 100 && image_width < 100

              best_attachment_url = image_url
              break
            end
          end
        end
      end

      date = parse_subject_for_date(@subject)
      existing_entry = @user.existing_entry(date.to_s)

      inspiration_id = parse_body_for_inspiration_id(@raw_body)

      @body = @html if @html.present? && @user.is_pro?

      if existing_entry.present?
        existing_entry.original_email = @inbound_email_params
        existing_entry.body += "<hr>#{@body}" if existing_entry.body.present?
        existing_entry.body = existing_entry.sanitized_body if @user.is_free?
        existing_entry.original_email_body = @raw_body
        existing_entry.inspiration_id = inspiration_id if inspiration_id.present?

        if existing_entry.image_url_cdn.blank? && best_attachment.present?
          existing_entry.image = best_attachment
        elsif existing_entry.image_url_cdn.blank? && best_attachment_url.present?
          existing_entry.remote_image_url = best_attachment_url
        end

        if existing_entry.save
          track_ga_event('Merged')

          if respond_as_ai? && @user && @user.is_admin?
            EntryMailer.respond_as_ai(@user, existing_entry).deliver_now
          end
        else
          # error saving entry
          Sentry.capture_message("Error processing entry via email", level: :error, extra: { reason: "Could not save exsiting entry", subject: @subject, entry_id: existing_entry&.id, errors: existing_entry&.errors })
          UserMailer.failed_entry(@user, existing_entry.errors.full_messages.to_sentence, date, @body).deliver_later
        end
      else
        params = { date: date, inspiration_id: inspiration_id }
        best_attachment.present? ? params.merge!(image: best_attachment) : params.merge!(remote_image_url: best_attachment_url)
        begin
          entry = @user.entries.create!(params.merge(body: @body, original_email_body: @raw_body))
        rescue ActiveRecord::RecordInvalid => error
          @error = error
          if error.to_s.include?("Image Failed to manipulate with MiniMagick")
            entry = @user.entries.create!(params.except(:image, :remote_image_url).merge(body: @body, original_email_body: @raw_body))
            Sentry.capture_message("Error processing image via email", level: :error, extra: { reason: "Image Failed to manipulate with MiniMagick", error: error, image: best_attachment, remote_image_url: best_attachment_url, subject: @subject, entry: entry })
          else
            Sentry.capture_message("Error processing entry via email", level: :error, extra: { reason: "ActiveRecord::RecordInvalid", error: error, subject: @subject })
          end
        rescue => error
          @error = error
          Sentry.capture_message("Error processing entry via email", level: :error, extra: { error: error, subject: @subject, body: @body, raw_body: @raw_body })
          @body = @body.force_encoding('iso-8859-1').encode('utf-8')
          @raw_body = @raw_body.force_encoding('iso-8859-1').encode('utf-8')
          entry = @user.entries.create!(params.merge(body: @body, original_email_body: @raw_body))
        end
        entry&.original_email = @inbound_email_params
        entry&.body = entry&.sanitized_body if @user.is_free?
        if entry&.save
          track_ga_event('New')
        else
          if entry.present?
            record_errors = entry.errors.to_s
          else
            record_errors = @error.to_s
          end
          Sentry.capture_message("Error processing entry via email", level: :error, extra: { reason: "Could not save new entry (failed_entry email sent to hello@dabble.me)", errors: entry&.errors, rescue_error: @error, body: @body, date: date })
          UserMailer.failed_entry(@user, record_errors, date, @body).deliver_later
        end
      end

      @user.increment!(:emails_received)
      begin
        UserMailer.second_welcome_email(@user).deliver_later if @user.emails_received == 1 && @user.entries.count == 1
      rescue StandardError => e
        Sentry.capture_message("Error sending email", level: :error, extra: { email_type: "Second Welcome Email" })
      end

      if entry.present? && respond_as_ai? && @user && @user.is_admin?
        EntryMailer.respond_as_ai(@user, entry).deliver_now
      end
    else # no user found
      Sentry.set_user(id: @token, email: @from)
      Sentry.capture_message("Inbound entry not associated to user", level: :error, extra: { subject: @subject, body: @body, html: @html, raw_body: @raw_body })
    end
  end

  private

  attr_reader :to, :cc, :bcc

  def all_recipients
    (to.to_a + cc.to_a + bcc.to_a)
  end

  def respond_as_ai?
    all_recipients.select { |k| k[:host] == ENV['SMTP_DOMAIN'].gsub('post', 'ai') }.any?
  end

  def track_ga_event(action)
    if ENV['GOOGLE_ANALYTICS_ID'].present?
      tracker = Staccato.tracker(ENV['GOOGLE_ANALYTICS_ID'])
      tracker.event(category: 'Email Entry', action: action, label: @user.user_key)
    end
  end

  def pick_meaningful_recipient(to_recipients, cc_recipients)
    host_to = to_recipients.select {|k| k[:host] =~ /^(email|post|ai)?\.?#{ENV['MAIN_DOMAIN'].gsub(".","\.")}$/i }.first
    if host_to.present?
      host_to[:token]
    elsif cc_recipients.present?
      # try CC's
      host_cc = cc_recipients.select {|k| k[:host] =~ /^(email|post|ai)?\.?#{ENV['MAIN_DOMAIN'].gsub(".","\.")}$/i }.first
      host_cc[:token] if host_cc.present?
    end
  end

  def find_user_from_user_key(to_token, from_email)
    begin
      user = User.find_by user_key: to_token
    rescue JSON::ParserError => e
    end
    user.blank? ? User.find_by(email: from_email) : user
  end

  def parse_subject_for_date(subject)
    # Find the date from the subject "It's Sept 2. How was your day?" and figure out the best year
    now = Time.now.in_time_zone(@user.send_timezone)
    parsed_date = Time.parse(subject) rescue now
    dates = [parsed_date, parsed_date.prev_year]
    dates_to_use = []
    dates.each do |d|
      dates_to_use << d if Time.now + 7.days - d > 0
    end
    if dates_to_use.blank?
      now.strftime('%Y-%m-%d')
    else
      dates_to_use.min_by { |d| (d - now).abs }.strftime('%Y-%m-%d')
    end
  end

  def unfold_paragraphs(body)
    return nil unless body.present?
    text  = ''
    body.split(/\n/).each do |line|
      if /\S/ !~ line
        text << "\n\n"
      else
        if line.length < 60 || /^(\s+|[*])/ =~ line
          text << (line.rstrip + "\n")
        else
          text << (line.rstrip + ' ')
        end
      end
    end
    text.gsub("\n\n\n", "\n\n")
  end

  def parse_body_for_inspiration_id(raw_body)
    inspiration_id = nil
    begin
      inspiration_id = Inspiration.without_imports_or_email_or_tips.select {|i| raw_body.downcase.include? i.body.first(71).downcase }.first&.id
    rescue
    end
    inspiration_id
  end

  def clean_message(body)
    return nil unless body.present?

    body = EmailReplyTrimmer.trim(body)

    body&.gsub!(/src=\"data\:image\/(jpeg|png)\;base64\,.*\"/, "src=\"\"") # remove embedded images
    body&.gsub!(/url\(data\:image\/(jpeg|png)\;base64\,.*\)/, "url()") # remove embedded images
    body&.gsub!(/\n\n\n/, "\n\n \n\n") # allow double line breaks
    body = unfold_paragraphs(body) unless @from.include?('yahoo.com') # fix wrapped plain text, but yahoo messes this up
    body&.gsub!(/\[image\:\ Inline\ image\ [0-9]{1,2}\]/, "(see attached image)") # remove "Inline image" text from griddler
    body&.gsub!(/(?:\n\r?|\r\n?)/, "<br>") # convert line breaks
    body = "<p>#{body}</p>" # basic formatting
    body&.gsub!(/<(http[s]?:\/\/\S*?)>/, "(\\1)") # convert links to show up
    body&.gsub!(/<br\s*\/?>$/, "")&.gsub!(/<br\s*\/?>$/, "")&.gsub!(/^$\n/, "") # remove last unnecessary line break
    body&.gsub!(/--( \*)?$\z/, "") # remove gmail signature break
    body&.gsub!(/<br\s*\/?>$/, "")&.gsub!(/<br\s*\/?>$/, "")&.gsub!(/^$\n/, "") # remove last unnecessary line break
    body = body&.strip

    return unless body.present?

    to_utf8(body)
  end

  def to_utf8(content)
    return unless content.present?

    begin
      detection = CharlockHolmes::EncodingDetector.detect(content)
      CharlockHolmes::Converter.convert content, detection[:encoding].gsub("IBM424_ltr", "UTF-8"), "UTF-8"
    rescue
      content
    end
  end

  def clean_html_version(html)
    return nil unless html.present?

    html = EmailReplyTrimmer.trim(html)

    return unless html.present?

    html&.gsub!("<html>", "")&.gsub!("</html>", "")&.gsub!("<body>", "")&.gsub!("</body>", "")&.gsub!("<head>", "")&.gsub!("</head>", "")

    html = Rinku.auto_link(html, :all, 'target="_blank"')
    html = ActionController::Base.helpers.sanitize(html, tags: %w(strong em a div span ul ol li b i br p hr u em blockquote), attributes: %w(href target))
    html = html.split("<br>--<br>").first # strip out gmail signature
    html&.gsub!(/<div style="display:none;border:0px;width:0px;height:0px;overflow:hidden;">.+<\/div>/, "") # remove hidden divs / tracking pixels
    html&.gsub!(/src=\"cid\:\S+\"/, "src=\"\" style=\"display: none;\"") # remove attached images showing as broken inline images
    html&.gsub!(/<br\s*\/?>$/, "")&.gsub!(/<br\s*\/?>$/, "")&.gsub!(/^$\n/, "") # remove last unnecessary line break

    to_utf8(html)
  end
end
# rubocop:enable Metrics/AbcSize
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/ClassLength
# rubocop:enable Metrics/PerceivedComplexity
# rubocop:enable Metrics/CyclomaticComplexity
