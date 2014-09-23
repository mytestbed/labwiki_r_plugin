
LW.execute_controller.add_tool('R Console',
  '<button class="btn" type="submit">New R Console</button>',
  function(form, status_cbk) {
    var opts = {
      action: 'new',
      col: 'execute',
      widget: 'r/console',
      // mime_type: mime_type,
    };
    LW.execute_controller.refresh_content(opts, 'POST', status_cbk);
    return false;
  }
);


// $(document).bind("ajaxError", function(evt) {
  // var i = 0;
// });
//
// $(document).bind("ajaxComplete", function(evt) {
  // var i = 0;
// });
