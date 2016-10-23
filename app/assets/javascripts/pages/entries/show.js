(function(){
  window.DABBLE.pages.Entries_random = window.DABBLE.pages.Entries_show = function(){

    $(document).keydown(function(e) {
        switch(e.which) {
            case 37: // left
              if ($('#previous-entry').length) {
                window.location = $('#previous-entry').attr('href');
              }
              break;

            case 39: // right
              if ($('#next-entry').length) {
                window.location = $('#next-entry').attr('href');
              }
              break;

            default: return; // exit this handler for other keys
        }
        e.preventDefault(); // prevent the default action (scroll / move caret)
    });

    $(".entry").on("swiperight", function(event) {
      if ($('#previous-entry').length) {
        window.location = $('#previous-entry').attr('href');
      }
    });

    $(".entry").on("swipeleft", function(event) {
      if ($('#next-entry').length) {
        window.location = $('#next-entry').attr('href');
      }
    });    

  };

}());