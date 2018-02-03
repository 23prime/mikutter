require_relative 'entity_class'
require_relative 'api'

module Plugin::Worldon
  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#application
  class Application < Diva::Model
    register :worldon_application, name: "Mastodonアプリケーション(Worldon)"

    field.string :name, required: true
    field.uri :website
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#emoji
  class Emoji < Diva::Model
    #register :worldon_emoji, name: "Mastodon絵文字(Worldon)"

    field.string :shortcode, required: true
    field.uri :static_url, required: true
    field.uri :url, required: true
  end

  class AttachmentMeta < Diva::Model
    #register :worldon_attachment_meta, name: "Mastodon添付メディア メタ情報(Worldon)"

    field.int :width
    field.int :height
    field.string :size
    field.string :aspect
  end

  class AttachmentMetaSet < Diva::Model
    #register :worldon_attachment_meta, name: "Mastodon添付メディア メタ情報セット(Worldon)"

    field.has :original, AttachmentMeta
    field.has :small, AttachmentMeta
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#attachment
  class Attachment < Diva::Model
    #register :worldon_attachment, name: "Mastodon添付メディア(Worldon)"

    field.string :id, required: true
    field.string :type, required: true
    field.uri :url
    field.uri :remote_url
    field.uri :preview_url, required: true
    field.uri :text_url
    field.string :description

    field.has :meta, AttachmentMetaSet
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#mention
  class Mention < Diva::Model
    #register :worldon_mention, name: "Mastodonメンション(Worldon)"

    field.uri :url, required: true
    field.string :username, required: true
    field.string :acct, required: true
    field.string :id, required: true
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#tag
  class Tag < Diva::Model
    #register :worldon_tag, name: "Mastodonタグ(Worldon)"

    field.string :name, required: true
    field.uri :url, required: true
  end

  class AccountSource < Diva::Model
    #register :worldon_account_source, name: "Mastodonアカウント追加情報(Worldon)"

    field.string :privacy
    field.bool :sensitive
    field.string :note
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#status
  class Account < Diva::Model
    include Diva::Model::UserMixin

    register :worldon_account, name: "Mastodonアカウント(Worldon)"

    field.string :id, required: true
    field.string :username, required: true
    field.string :acct, required: true
    field.string :display_name, required: true
    field.bool :locked, required: true
    field.time :created_at, required: true
    field.int :followers_count, required: true
    field.int :following_count, required: true
    field.int :statuses_count, required: true
    field.string :note, required: true
    field.uri :url, required: true
    field.uri :avatar, required: true
    field.uri :avatar_static, required: true
    field.uri :header, required: true
    field.uri :header_static, required: true
    field.has :moved, Account
    field.has :source, AccountSource

    alias_method :perma_link, :url
    alias_method :uri, :url
    alias_method :idname, :acct
    alias_method :name, :display_name
    alias_method :description, :note

    def self.domain(url)
      Diva::URI.new(url).host
    end

    def self.regularize_acct(hash)
      if hash[:acct].index('@').nil?
        hash[:acct] = hash[:acct] + '@' + self.domain(hash[:url])
      end
      hash
    end

    def initialize(hash)
      hash[:created_at] = Time.parse(hash[:created_at]).localtime
      hash = self.class.regularize_acct(hash)

      # activity対策
      hash[:idname] = hash[:acct]

      super hash
    end

    def title
      "#{acct}(#{display_name})"
    end

    def icon
      Plugin.filtering(:photo_filter, avatar, [])[1].first
    end
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#status
  class Status < Diva::Model
    include Diva::Model::MessageMixin

    register :worldon_status, name: "Mastodonステータス(Worldon)", timeline: true, reply: true, myself: true

    field.string :id, required: true
    field.uri :url, required: true
    field.has :account, Plugin::Worldon::Account, required: true
    field.string :in_reply_to_id
    field.string :in_reply_to_account_id
    field.has :reblog, Plugin::Worldon::Status
    field.string :content, required: true
    field.time :created_at, required: true
    field.time :created
    field.int :reblogs_count
    field.int :favourites_count
    field.bool :reblogged
    field.bool :favourited
    field.bool :muted
    field.bool :sensitive
    field.string :visibility
    field.bool :sensitive?
    field.string :spoiler_text
    field.string :visibility
    field.has :application, Application
    field.string :language
    field.bool :pinned

    field.string :domain, required: true # APIには無い追加フィールド

    field.has :emojis, [Emoji]
    field.has :media_attachments, [Attachment]
    field.has :mentions, [Mention]
    field.has :tags, [Tag]

    alias_method :uri, :url # mikutter側の都合で、URI.parse可能である必要がある（API仕様上のuriフィールドとは異なる）。
    alias_method :perma_link, :url
    alias_method :shared?, :reblogged
    alias_method :favorite?, :favourited
    alias_method :muted?, :muted
    alias_method :pinned?, :pinned
    alias_method :retweet_ancestor, :reblog

    @mute_mutex = Thread::Mutex.new

    entity_class MastodonEntity

    class << self
      def add_mutes(account_hashes)
        @mute_mutex.synchronize {
          @mutes ||= []
          @mutes += account_hashes.map do |hash|
            hash = Account.regularize_acct hash
            hash[:acct]
          end
          @mutes = @mutes.uniq
          #pp @mutes
        }
      end

      def build(domain_name, json)
        return [] if json.nil?
        json.map do |record|
          record[:domain] = domain_name
          if record[:reblog]
            record[:reblog][:domain] = domain_name
          end
          Status.new(record)
        end.compact
      end
    end

    def initialize(hash)
      @mutes ||= []
      if hash[:account] && hash[:account][:acct]
        account_hash = Account.regularize_acct(hash[:account])
        if @mutes.index(account_hash[:acct])
          return nil
        end
      end

      # タイムゾーン考慮
      hash[:created_at] = Time.parse(hash[:created_at]).localtime
      # cairo_sub_parts_message_base用
      hash[:created] = hash[:created_at]

      # mikutterはuriをURI型であるとみなす
      hash[:original_uri] = hash[:uri]
      hash.delete :uri

      # sub_parts_client用
      if hash[:application] && hash[:application][:name]
        hash[:source] = hash[:application][:name]
      end

      super hash

      self[:user] = self[:account]
      if self[:reblog]
        self[:reblog][:user] = self[:reblog][:account]
      end
    end

    def actual_status
      if reblog.nil?
        self
      else
        reblog
      end
    end

    def user
      account
    end

    def retweet_count
      actual_status.reblogs_count
    end

    def favorite_count
      actual_status.favourites_count
    end

    def retweet?
      reblog.is_a? Status
    end

    def retweeted_by
      if reblog.nil?
        []
      else
        [account]
      end
    end

    # NSFW系プラグイン用
    def sensitive?
      sensitive
    end

    # sub_parts_client用
    def source
      if actual_status.application
        actual_status.application.name
      else
        nil
      end
    end

    def dehtmlize(text)
      text
        .gsub(/<span class="ellipsis">([^<]*)<\/span>/) {|s| $1 + "..." }
        .gsub(/^<p>|<\/p>|<span class="invisible">[^<]*<\/span>|<\/?span[^>]*>/, '')
        .gsub(/<br[^>]*>|<p>/) { "\n" }
    end

    def description
      msg = actual_status
      desc = dehtmlize(msg.content)
      if !msg.spoiler_text.nil? && msg.spoiler_text.size > 0
        desc = dehtmlize(msg.spoiler_text) + "\n----\n" + desc
      end
      desc
    end

    # register reply:true用API
    def mentioned_by_me?
      !mentions.empty? && myself?
    end

    # register myself:true用API
    def myself?
      Plugin.filtering(:worldon_worlds, nil).first.select{|world|
        actual_status.user.acct == world.account.acct
      }.map{|_|
        true
      }.any?
    end

    # Basis Model API
    def title
      msg = actual_status
      if !msg.spoiler_text.nil? && msg.spoiler_text.size > 0
        msg.spoiler_text
      else
        msg.content
      end
    end

    # activity用
    def to_s
      dehtmlize(title)
    end

    # ふぁぼ
    def favorite(do_fav)
      world, = Plugin.filtering(:world_current, nil)
      if do_fav
        Plugin[:worldon].favorite(world, self)
      else
        # TODO: unfavorite spell
      end
    end

    def retweeted_statuses
      # TODO: APIで個別取得するタイミングがわからないので適当
      if reblog.nil?
        []
      else
        [self]
      end
    end

    # quoted_message用
    def quoting?
      content = actual_status.content
      r = %r!<a [^>]*href="https://(?:[^/]+/@[^/]+/\d+|twitter\.com/[^/]+/status/\d+)"!.match(content).nil?
      !r
    end

    # quoted_message用
    def quoting_messages(force_retrieve=false)
      content = actual_status.content
      matches = []
      regexp = %r!<a [^>]*href="(https://(?:[^/]+/@[^/]+/\d+|twitter\.com/[^/]+/\d+))"!
      rest = content
      while m = regexp.match(rest)
        matches.push m.to_a
        rest = m.post_match
      end
      matches
        .map do |m|
          url = m[1]
          if url.index('twitter.com')
            # TODO: 可能ならMessageをリモートから取得
            Plugin::Twitter::Message.findbyid(quoted_id, -1)
          else
            m = %r!https://([^/]+)/@[^/]+/(\d+)!.match(url)
            next nil if m.nil?
            domain_name = m[1]
            id = m[2]
            resp = Plugin::Worldon::API.status(domain_name, id)
            next nil if resp.nil?
            Status.build(domain_name, [resp]).first
          end
        end.compact
    end

    # 返信スレッド用
    def around(force_retrieve=false)
      resp = Plugin::Worldon::API.call(:get, domain, '/api/v1/statuses/' + id + '/context')
      return [self] if resp.nil?
      ancestors = Status.build(domain, resp[:ancestors])
      descendants = Status.build(domain, resp[:descendants])
      ancestors + [self] + descendants
    end

    # 返信表示用
    def has_receive_message?
      !in_reply_to_id.nil?
    end

    # 返信表示用
    def replyto_source(force_retrieve=false)
      if domain.nil?
        # 何故かreplyviewerに渡されたStatusからdomainが消失することがあるので復元を試みる
        world = Plugin.filtering(:current_worldon, nil)
        if !world.nil?
          # 見つかったworldでstatusを取得し、id, domain, in_reply_to_idを上書きする。
          status = Plugin::Worldon::API.status_by_url(world.domain, world.access_token, url)
          if !status.nil?
            self[:id] = status[:id]
            self[:domain] = world.domain
            self[:in_reply_to_id] = status[:in_reply_to_id]
            if status[:reblog]
              self.reblog[:id] = status[:reblog][:id]
              self.reblog[:domain] = world.domain
              self.reblog[:in_reply_to_id] = status[:reblog][:in_reply_to_id]
            end
          end
        end
      end
      resp = Plugin::Worldon::API.status(domain, in_reply_to_id)
      return nil if resp.nil?
      Status.build(domain, [resp]).first
    end

    # 返信表示用
    def replyto_source_d(force_retrieve=true)
      promise = Delayer::Deferred.new(true)
      Thread.new do
        begin
          result = replyto_source(force_retrieve)
          if result.is_a? Status
            promise.call(result)
          else
            promise.fail(result)
          end
        rescue Exception => e
          promise.fail(e)
        end
      end
      promise
    end

    def retweet_source(force_retrieve=false)
      reblog
    end

    def retweet_source_d
      promise = Delayer::Deferred.new(true)
      Thread.new do
        begin
          if reblog.is_a? Status
            promise.call(reblog)
          else
            promise.fail(reblog)
          end
        rescue Exception => e
          promise.fail(e)
        end
      end
      promise
    end

    def retweet_ancestors(force_retrieve=false)
      if reblog.is_a? Status
        [self, reblog]
      else
        [self]
      end
    end

  end
end
