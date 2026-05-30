# frozen_string_literal: true

module Agents
  class ResolveInterruptService
    def self.call(interrupt:, resolver:, action:, edited_message: nil)
      new(interrupt: interrupt, resolver: resolver, action: action, edited_message: edited_message).call
    end

    def initialize(interrupt:, resolver:, action:, edited_message: nil)
      @interrupt = interrupt
      @resolver = resolver
      @action = action.to_s
      @edited_message = edited_message
      @client = Langgraph::Client.new
    end

    def call
      raise ArgumentError, "interrupt already resolved" unless @interrupt.status == "pending"

      resolution = build_resolution
      @client.resume!(thread_id: @interrupt.thread_id, resolution: resolution)

      @interrupt.update!(
        status: resolution_status,
        resolution: resolution,
        resolved_by_type: @resolver.class.name,
        resolved_by_id: @resolver.id,
        resolved_at: Time.current
      )

      deliver_discovery_reply if @interrupt.kind == "discovery_reply" && resolution_status != "rejected"
      publish_opportunity_recommendations if @interrupt.kind == "opportunity_recommendation" && resolution_status != "rejected"

      @interrupt
    end

    private

    def build_resolution
      case @action
      when "approve"
        {
          "action" => "approve",
          "assistant_message" => @interrupt.payload["assistant_message"]
        }
      when "edit"
        {
          "action" => "edit",
          "edited_message" => @edited_message.presence || @interrupt.payload["assistant_message"]
        }
      else
        { "action" => "reject" }
      end
    end

    def resolution_status
      case @action
      when "approve" then "approved"
      when "edit" then "edited"
      else "rejected"
      end
    end

    def deliver_discovery_reply
      conversation = @interrupt.conversation
      employee = @interrupt.employee
      return unless conversation && employee

      body = case @action
             when "edit" then @edited_message
             else @interrupt.payload["assistant_message"]
             end
      return if body.blank?

      handler = Whatsapp::DiscoveryHandler.new(employee: employee, conversation: conversation)
      handler.deliver_assistant_reply(
        "assistant_message" => body,
        "completed" => false,
        "delayed" => false
      )
    end

    def publish_opportunity_recommendations
      recs = @interrupt.payload["recommendations"] || []
      return if recs.blank?

      Intelligence::RecommendationUpsertService.call(
        company: @interrupt.company,
        recommendations: recs.map { |r| r.deep_symbolize_keys.except(:evidence, :source, :effort, :timeframe) }
      )
    end
  end
end
