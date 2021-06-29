# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2021_06_29_014303) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "entries", id: :serial, force: :cascade do |t|
    t.datetime "date", null: false
    t.text "body"
    t.text "filepicker_url"
    t.text "original_email_body"
    t.integer "inspiration_id"
    t.integer "user_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "image"
    t.jsonb "songs", default: [], array: true
    t.index ["user_id"], name: "index_entries_on_user_id"
  end

  create_table "hashtags", force: :cascade do |t|
    t.bigint "user_id"
    t.string "tag"
    t.date "date"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id"], name: "index_hashtags_on_user_id"
  end

  create_table "inspirations", id: :serial, force: :cascade do |t|
    t.string "category"
    t.text "body"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "payments", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.decimal "amount", precision: 8, scale: 2, default: "0.0"
    t.text "comments"
    t.datetime "date"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.inet "current_sign_in_ip"
    t.inet "last_sign_in_ip"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "first_name"
    t.string "last_name"
    t.string "send_timezone", default: "Mountain Time (US & Canada)"
    t.boolean "send_past_entry", default: true
    t.integer "emails_sent", default: 0
    t.integer "emails_received", default: 0
    t.time "send_time", default: "2000-01-01 20:00:00", null: false
    t.string "user_key"
    t.text "plan", default: "Free"
    t.string "gumroad_id"
    t.string "referrer"
    t.string "past_filter"
    t.boolean "way_back_past_entries", default: true
    t.string "paranoid_verification_code"
    t.integer "paranoid_verification_attempt", default: 0
    t.datetime "paranoid_verified_at"
    t.string "payhere_id"
    t.string "stripe_id"
    t.string "failed_attempts", default: "0", null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.integer "emails_bounced", default: 0
    t.text "frequency", default: ["Sun"], array: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["paranoid_verification_code"], name: "index_users_on_paranoid_verification_code"
    t.index ["paranoid_verified_at"], name: "index_users_on_paranoid_verified_at"
    t.index ["plan"], name: "index_users_on_plan"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["user_key"], name: "index_users_on_user_key", unique: true
  end

end
