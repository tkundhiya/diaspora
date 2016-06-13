#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

class Retraction
  include Diaspora::Federated::Base
  include Diaspora::Logging

  attr_reader :subscribers, :data

  def initialize(data, subscribers, target=nil)
    @data = data
    @subscribers = subscribers
    @target = target
  end

  def self.for(target, sender=nil)
    federation_retraction = case target
                            when Diaspora::Relayable
                              Diaspora::Federation::Entities.relayable_retraction(target, sender)
                            when Post
                              Diaspora::Federation::Entities.signed_retraction(target, sender)
                            else
                              Diaspora::Federation::Entities.retraction(target)
                            end

    new(federation_retraction.to_h, target.subscribers.select(&:remote?), target)
  end

  def defer_dispatch(user)
    Workers::DeferredRetraction.perform_async(user.id, data, subscribers.map(&:id), service_opts(user))
  end

  def perform
    logger.debug "Performing retraction for #{target.class.base_class}:#{target.guid}"
    target.destroy!
    logger.info "event=retraction status=complete target=#{data[:target_type]}:#{data[:target_guid]}"
  end

  def public?
    data[:target][:public]
  end

  private

  attr_reader :target

  def service_opts(user)
    return {} unless target.is_a?(StatusMessage)

    user.services.each_with_object(service_types: []) do |service, opts|
      service_opts = service.post_opts(target)
      if service_opts
        opts.merge!(service_opts)
        opts[:service_types] << service.class.to_s
      end
    end
  end
end
