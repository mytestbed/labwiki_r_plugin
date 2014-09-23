
OML.require_dependency('vendor/slickgrid/slick.core', ['vendor/jquery/jquery.event.drag']);
OML.require_dependency('vendor/slickgrid/slick.formatters', ['vendor/slickgrid/slick.core']);
OML.require_dependency('vendor/slickgrid/slick.editors', ['vendor/slickgrid/slick.core']);
OML.require_dependency('vendor/slickgrid/plugins/slick.rowselectionmodel', ['vendor/slickgrid/slick.core']);
OML.require_dependency('vendor/slickgrid/slick.grid', ['vendor/slickgrid/slick.core']);
OML.require_dependency('vendor/slickgrid/slick.dataview', ['vendor/slickgrid/slick.core']);
OML.require_dependency('vendor/slickgrid/controls/slick.pager', ['vendor/slickgrid/slick.core']);
OML.require_dependency('vendor/slickgrid/controls/slick.columnpicker', ['vendor/slickgrid/slick.core']);

define(['theme/labwiki/js/labwiki', 'vendor/slickgrid/slick.grid', 'css!theme/bright/css/slickgrid', 'vendor/spin/jquery.spin'],
  function (LW, FormBuilder) {

    var console = function(container, controller, opts) {
      var input_height = 45;

      var input_line_no = 0;
      var output_line_no = 0;
      var output_height = 0;
      var widget = $('#' + opts.wid);
      var output_div = widget.find('.r_output_block');
      var output_wrapper = output_div.find('.wrapper');
      var toolbar_buttons = {};
      var input_is_incomplete = false;
      var input_line = null;

      function widget() {};

      function process_line(l) {
        var hl = create_output_record(input_line_no += 1, 0, l);
        if (hl) output_wrapper.append(hl);
        output_bottom_flush();
        input_line = l;
        input_is_incomplete = false;

        // Send it to the backend for processing
        var cmd = {
          action: 'eval_line',
          col: 'execute',
          input: l,
          line_no: input_line_no
        };
        controller.request_action(cmd, 'POST');
      }

      function input_incomplete() {
        input_is_incomplete = true;
      }

      // Make the output lines bottom flushed
      function output_bottom_flush() {
        var wh = output_wrapper.height();
        var pad_t = output_height - wh;
        if (pad_t < 0) pad_t = 0;

        output_div.css('padding-top', '' + pad_t + 'px');
        if (pad_t == 0) {
          // ALways show the last line
          output_div.animate({ scrollTop: wh }, 1000);
        }
      }

      // Return a 'div' describing a single R interaction
      // ... line_no, state, type, input, output
      function create_output_record(line_no, part_no, input, state, klass, type, output,svg) {
        var id = opts.wid + '_l' + line_no;
        var incomplete_line = (klass == 'incomplete-line');

        var hl = $('<div class="r_line"/>').attr('id', id);
        hl.addClass("r_line_" + (part_no == 0 ? 'first' : 'cont'));
        var in_div = $('<div class="r_input_cmd"/>');
        hl.append(in_div);
        var prompt = $('<div class="prompt"/>');
        prompt.text((part_no > 0) ? '+' : '>');
        in_div.append(prompt);
        in_div.append($('<div class="cmd"/>').text(input));

        var out_div = $('<div class="r_output"/>');
        hl.append(out_div);
        if (output == null) {
          // Show spinning wheel for complete lines
          update_spinner(!incomplete_line, line_no, out_div);
        } else if (!incomplete_line){
          var res_div = $('<div class="result"/>');
          res_div = format_output_line(output, svg, line_no, part_no, state, klass, type, res_div);
          if (res_div) {
            out_div.append(res_div);
          }
        }
        update_input_prompt(line_no, part_no, incomplete_line);
        return hl;
      }

      function update_spinner(on, line_no, div) {
        if (! div) {
          var id = opts.wid + '_l' + line_no;
          div = $('#' + id + ' .r_output');
        }
        if (on) {
          // Show spinning wheel
          sopts = { lines: 8, length: 4, width: 3, radius: 2, position: 'relative',
                    top: '12px', left: '12px' };
          div.append($('<div class="spinner_c"/>').spin(sopts, 'black'));
          var i = 0;
        } else {
          div.empty(); // remove spinner
        }
        var i = 0;
      }

      function update_input_prompt(line_no, part_no, incomplete_line) {
        var iprompt = $('#' + opts.wid + '_input_prompt');
        iprompt.text((incomplete_line && input_line_no == line_no) ? '+' : '>');
        var i = 0;
      }

      // Update the input for output line 'line_no'
      function update_output_input(line_no, input) {
        var id = opts.wid + '_l' + line_no;
        var cmd = $("#" + id).find(".cmd");
        cmd.text(input);
      }

      function format_output_line(output, svg, line_no, part_no, state, klass, type, res_div) {
        switch(klass) {
          case 'try-error': {
            return format_try_error(res_div, output);
          }
        }
        var val = output.val;
        if (svg) {
          format_output_graph(svg, output, line_no, part_no, state, klass, type, res_div);
        } else if (_.isArray(val)) {
          format_output_table(output, line_no, part_no, state, klass, type, res_div);
        } else {
          res_div.text(output.val);
        }
        return res_div;
      }

      function format_output_table(output, line_no, part_no, state, klass, type, res_div) {
        var id = opts.wid + '_t' + line_no;
        res_div.attr('id', id);
        var is_array = (output.names == null);
        var names = is_array ? ['value'] : output.names;
        var columns = _.map(names, function(n, i) {
          return {id: n, name: n, title: n, field: i + 1};
        });
        columns.unshift({id: '_index_', name: 'index', title: 'index', field: 0, cssClass: 'index', headerCssClass: 'index'}); // add array index

        var options = {
          headerRowHeight: 30,
          rowHeight: 25,
          topPanelHeight: 30,

          defaultColumnWidth: 80,

          editable: false,
          enableAddRow: false,
          enableCellNavigation: false,
          enableColumnReorder: true,
          //forceFitColumns: true
        };

        var val = output.val;
        var row_cnt = is_array ? val.length : val[0].length;
        function getMItem(index) {
          var row = _.map(val, function(c) {
            return c[index];
          });
          row.unshift(index);
          return row;
        }
        function getAItem(index) {
          return [index, val[index]];
        }
        function getLength() {
          return row_cnt;
        }
        setTimeout(function() {
          var rows = row_cnt + 1; // +1 ... header
          if (rows > 10) rows = 10;
          var h = rows * options.rowHeight;
          res_div.height(h + 10);

          //res_div.css('width', '' + w + 30 + 'px');

          var grid = new Slick.Grid("#" + id, {getLength: getLength, getItem: (is_array ? getAItem : getMItem)}, columns, options);
          // res_div.css('height', '300px');
          // grid.resizeCanvas();
          grid.updateRowCount(); // fixes scroll bar
          grid.invalidateAllRows();
          grid.render();

          // Fixing CSS issues. May break things later
          var w = columns.length * (options.defaultColumnWidth + 4);
          res_div.width(w + 30) // 30 ... safety margin
            .height(h + 10)
            ;
          var h = res_div.find('.slick-header-column');
          h.css('height', 'auto').css('width', '' + options.defaultColumnWidth + 'px');

          output_bottom_flush();
        }, 1000);
      }

      function format_output_graph(svg, output, line_no, part_no, state, klass, type, res_div) {
        var s = $(svg).filter('svg');

        var w = parseInt(s.attr('width'));
        var h = parseInt(s.attr('height'));
        var r = 1.0 * h / w;
        s.attr('width', '100%');
        s.attr('height', '' + (100 * r) + '%');

        res_div.append(s);

        s.data('content', function() {
          return {type: 'svg', svg: svg };
        });
        s.data('embedder', function(embed_container) {
          embed_container.append(s.clone());
        });

        s.draggable({
          appendTo: "body",
          cursorAt: { top: 50, left: 50 },
          helper: function(ev) {
            var d = s.clone();
            d.attr('width', '100px');
            d.attr('height', '' + 100 * r + 'px');
            return d;
          },
          stack: 'body',
          zIndex: 9999
        });
        var i = 0;
      }

      var eval_error_rx = /Error in eval[^:]*:(.*)/;
      function format_try_error(res_div, output) {
        var res = null;
        var msg = output.msg;
        res_div.addClass('error');
        if (res = eval_error_rx.exec(msg)) {
          res_div.text(res[1]);
        } else if (res = incomplete_line_rx.exec(msg)) {
          input_incomplete();
          return null;
        } else {
          res_div.text(msg);
        }
        return res_div;
      }

      function update_output(evt) {
        var ds = evt.data_source;
        var msgs = ds.rows(); //.events;
        var flush_bottom = false;
        _.each(msgs, function(r) {
          // __id__, line_no, input, state, type, class, output
          var lno = r[1];
          var pno = r[2];
          var input = r[3];
          var state = r[4];
          var type = r[5];
          var klass = r[6];
          var output = r[7];
          var svg = r[8];
          var replace = append = false;

          if (lno == -1) { // backend reporting R version
            r_version(output);
            return;
          }
          if (lno > input_line_no) {
            input_line_no = output_line_no = lno;
            var hl = create_output_record(lno, pno, input, state, klass, type, output, svg);
            if (hl) output_wrapper.append(hl);
            flush_bottom = true;
          } else if (lno > output_line_no) {
            output_line_no = lno; // hl == 0 is for incomplete lines
            var hl = create_output_record(lno, pno, input, state, klass, type, output, svg);
            if (hl) {
              var id = hl.attr('id');
              var old_hl = $('#' + id);
              old_hl.replaceWith(hl);
              hl.effect("highlight", "slow");
            }
            flush_bottom = true;
          }
        });
        if (flush_bottom) output_bottom_flush();
      }

      function r_version(version) {
        var wc = widget.parents('.widget-content');
        var st = wc.find('.widget-title-block .sub_title');
        st.text(version);
      }

      // ======= INIT ======

      OHUB.bind('data_source.' + opts.output_source_id + '.changed', update_output);

      var ci = widget.find('.input');
      ci.keypress(function(ev) {
        switch (ev.keyCode) {
          case 13: {
            var l = ci.val();
            ci.val('');
            process_line(l);
            return true;
          }
          case 38: { // cursor UP
            //process_up_arrow();
            return true;
          }
          case 40: { // cursor DOWN
            //process_down_arrow();
            return true;
          }
        }
        return true;
      });


      OHUB.bind('column.execute.resize', function(dim) {
        var h = dim.panel_height;
        var oh = output_height = h - input_height;

        var ow = widget.find('.r_output_block');
        ow.height(oh);

        var iw = widget.find('.r_input_block');
        iw.height(input_height);

        output_bottom_flush();
      });
      //resize({width: c.width()});

      // Toolbar buttons
      var c = controller;
      var b = toolbar_buttons;

      b.reset = c.add_toolbar_button({name: 'reset', awsome: 'times-circle', tooltip: 'Reset Session', active: true},
        function() {
          // Send it to the backend for processing
          var cmd = {
            action: 'reset',
            col: 'execute',
          };
          controller.request_action(cmd, 'POST', function(success) {
            if (success == true) {
              c.show_alert('success', 'R Session reset.');
              $('#' + opts.wid + ' .wrapper').empty(); // clear output list
            } else {
              c.show_alert('warning', 'Something went wrong while resetting R Session.');
            }
          });
        });

      /** Let's only have one active console **/
      $('#new_r_console_form_execute button').text("Show R Console");

      // Make sure we are hitting some of the callbacks
      controller.init_content_panel();
      return widget;

    };

    return console;
  }
);
