# -*- coding: utf-8 -*-

require 'net/http'

Plugin.create :bugreport do

  on_boot do |service|
    begin
      popup if crashed_exception.is_a? Exception
    rescue => e
      # バグ報告中にバグで死んだらつらいもんな
      error e end end

  def popup
    alert_thread = if(Thread.main != Thread.current) then Thread.current end
    dialog = Gtk::Dialog.new("bug report")
    dialog.set_size_request(600, 400)
    dialog.window_position = Gtk::Window::POS_CENTER
    dialog.vbox.pack_start(main, true, true, 30)
    dialog.add_button(Gtk::Stock::OK, Gtk::Dialog::RESPONSE_OK)
    dialog.add_button(Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL)
    dialog.default_response = Gtk::Dialog::RESPONSE_OK
    quit = lambda{
      dialog.hide_all.destroy
      Gtk.main_iteration_do(false)
      if alert_thread
        alert_thread.run
      else
        Gtk.main_quit
      end }
    dialog.signal_connect("response"){ |widget, response|
      if response == Gtk::Dialog::RESPONSE_OK
        send
      else
        File.delete(File.expand_path(File.join(Environment::TMPDIR, 'mikutter_error'))) rescue nil
        File.delete(File.expand_path(File.join(Environment::TMPDIR, 'crashed_exception'))) rescue nil end
      quit.call }
    dialog.signal_connect("destroy") {
      false
    }
    dialog.show_all
    if(alert_thread)
      Thread.stop
    else
      Gtk::main
    end
  end

  def imsorry
    _("%{mikutter} が突然終了してしまったみたいで ヽ('ω')ﾉ三ヽ('ω')ﾉもうしわけねぇもうしわけねぇ")%{mikutter: Environment::NAME}+"\n"+
      _('OKボタンを押したら、自動的に以下のテキストが送られます。これがバグを直すのにとっても役に立つんですよ。よかったら送ってくれません？')
  end

  def main
    Gtk::VBox.new(false, 0).
      closeup(Gtk::IntelligentTextview.new(imsorry)).
      pack_start(Gtk::ScrolledWindow.
                 new.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_ALWAYS).
                 add(Gtk::IntelligentTextview.new(backtrace)))
  end

  def send
    Thread.new{
      begin
        exception = crashed_exception
        m = exception.backtrace.first.match(/(.+?):(\d+)/)
        crashed_file, crashed_line = m[1], m[2]
        param = {
          'backtrace' => JSON.generate(exception.backtrace.map{ |msg| msg.gsub(FOLLOW_DIR, '{MIKUTTER_DIR}') }),
          'file' => crashed_file.gsub(FOLLOW_DIR, '{MIKUTTER_DIR}'),
          'line' => crashed_line,
          'exception_class' => exception.class,
          'description' => exception.to_s,
          'ruby_version' => RUBY_VERSION,
          'rubygtk_version' => Gtk::BINDING_VERSION.join('.'),
          'platform' => RUBY_PLATFORM,
          'url' => 'exception',
          'version' => Environment::VERSION }
        case exception
        when TypeStrictError
          param['causing_value'] = exception.value
        end
        Net::HTTP.start('mikutter.hachune.net', 4567){ |http|
          console = mikutter_error
          param['stderr'] = console if console
          eparam = encode_parameters(param)
          http.post('/', eparam) }
        File.delete(File.expand_path(File.join(Environment::TMPDIR, 'mikutter_error'))) rescue nil
        File.delete(File.expand_path(File.join(Environment::TMPDIR, 'crashed_exception'))) rescue nil
        Plugin.activity :system, _("エラー報告を送信しました。ありがとう♡")
        Plugin.call :send_bugreport, param
      rescue Timeout::Error, StandardError => e
        Plugin.activity :system, _("ﾋﾟｬｱｱｱｱｱｱｱｱｱｱｱｱｱｱｱｱｱｱｱｱｱｱｱwwwwwwwwwwwwwwwwwwwwww")
        Plugin.activity :error, e.to_s, exception: e
      end } end

  def revision
    begin
      open('|env LC_ALL=C svn info').read.match(/Revision\s*:\s*(\d+)/)[1]
    rescue
      '' end end

  def mikutter_error
    name = File.expand_path(File.join(Environment::TMPDIR, 'mikutter_error'))
    if FileTest.exist?(name)
      file_get_contents(name) end end

  def backtrace
    "#{crashed_exception.class} #{crashed_exception.to_s}\n" +
      crashed_exception.backtrace.map{ |msg| msg.gsub(FOLLOW_DIR, '{MIKUTTER_DIR}') }.join("\n")
  end

  def crashed_exception
    @crashed_exception ||= object_get_contents(File.expand_path(File.join(Environment::TMPDIR, 'crashed_exception'))) rescue nil
  end

  def encode_parameters(params, delimiter = '&', quote = nil)
    if params.is_a?(Hash)
      params = params.map do |key, value|
        "#{escape(key)}=#{quote}#{escape(value)}#{quote}"
      end
    else
      params = params.map { |value| escape(value) }
    end
    delimiter ? params.join(delimiter) : params
  end

  def escape(value)
    URI.escape(value.to_s, /[^a-zA-Z0-9\-\.\_\~]/)
  end

end
