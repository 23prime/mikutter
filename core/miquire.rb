# -*- coding: utf-8 -*-
# 多くの人に最初に突っ込まれるメソッドを定義する

require 'set'

$LOAD_PATH.
  unshift(File.expand_path(File.join(File.dirname(__FILE__)))).
  unshift(File.expand_path(File.join(File.dirname(__FILE__), '../vendor/'))).
  unshift(File.expand_path(File.join(File.dirname(__FILE__), 'lib')))

# ミクってかわいいよねぇ。
# ツインテールいいよねー。
# どう良いのかを書くとコードより長くなりそうだから詳しくは書かないけどいいよねぇ。
# ふたりで寒い時とかに歩いてたら首にまいてくれるんだよー。
# 我ながらなんてわかりやすい説明なんだろう。
# (訳: Miquire::miquire のエイリアス)
def miquire(*args)
  Miquire.miquire(*args)
end

module Miquire
  class << self

    PATH_KIND_CONVERTER = Hash.new{ |h, k| h[k] = k.to_s + '/' }
    # PATH_KIND_CONVERTER[:mui] = 'mui/gtk_'
    PATH_KIND_CONVERTER[:mui] = Class.new{
      define_method(:+){ |other|
        render = lambda{ |r| File.join('mui', "#{r}_" + other) }
        if other == '*' or FileTest.exist?(File.join(File.dirname(__FILE__), render[:cairo] + '.rb'))
          render[:cairo]
        else
          render[:gtk] end } }.new
    PATH_KIND_CONVERTER[:core] = File.expand_path(File.join(File.dirname(__FILE__)))+"/"
    PATH_KIND_CONVERTER[:user_plugin] = '../plugin/'
    PATH_KIND_CONVERTER[:lib] = Class.new{
      define_method(:+){ |other|
        render = lambda{ |r| File.join(r, other) }
        if FileTest.exist?(render["../vendor"] + '.rb')
          render["../vendor"]
        elsif FileTest.exist?(render["lib"] + '.rb')
          render["lib"]
        else
          other end } }.new

    # CHIのコアソースコードファイルを読み込む。
    # _kind_ はファイルの種類、 _file_ はファイル名（拡張子を除く）。
    # _file_ を省略すると、そのディレクトリ下のrubyファイルを全て読み込む。
    # その際、そのディレクトリ下にディレクトリがあれば、そのディレクトリ内に
    # そのディレクトリと同じ名前のRubyファイルがあると仮定して読み込もうとする。
    # == Example
    #  miquire :plugin
    # == Directory hierarchy
    #  plugins/
    #  + a.rb
    #  `- b/
    #     + README
    #     + b.rb
    #     ` c.rb
    #  a.rbとb.rbが読み込まれる(c.rbやREADMEは読み込まれない)
    def miquire(kind, *files)
      kind = kind.to_sym
      if files.empty?
        miquire_all_files(kind)
      else
        if kind == :lib
          files.each{ |file|
            path = File.expand_path(PATH_KIND_CONVERTER[:lib] + file)
            directory = File.dirname(path)
            if FileTest.exist?(directory)
              Dir.chdir(File.dirname(path)) {
                miquire_original_require file }
            else
              miquire_original_require file end }
        else
          files.each{ |file|
            file_or_directory_require PATH_KIND_CONVERTER[kind] + file.to_s } end end end

    # miquireと同じだが、全てのファイルが対象になる
    def miquire_all_files(kind)
      kind = kind.to_sym
      Dir.glob(PATH_KIND_CONVERTER[kind] + '*'.freeze).select{ |x| FileTest.directory?(x) or x.end_with?('.rb'.freeze) }.sort.each{ |rb|
        file_or_directory_require(rb) } end

    def file_or_directory_require(rb)
      if(match = rb.match(/\A(.*)\.rb\Z/))
        rb = match[1] end
      case
      when FileTest.directory?(File.join(rb))
        plugin = (File.join(rb, File.basename(rb)))
        if FileTest.exist? plugin or FileTest.exist? "#{plugin}.rb"
          miquire_original_require plugin
        else
          miquire_original_require rb end
      else
        miquire_original_require rb end end

    def miquire_original_require(file)
      require file end
  end

  class LoadError < StandardError; end
end
