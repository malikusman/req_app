# frozen_string_literal: true

module DeepDivePlans
  class Workflow
    class Conflict < StandardError; end

    STALE_AFTER = 10.minutes

    def initialize(run, actor)
      @run, @actor = run, actor
      review = TaskSelectionReview.find_by(task_intelligence_run: run, company_id: run.company_id)
      @selection = review&.revisions&.order(version: :desc)&.first
      raise Conflict, "Finalize task selection before opening Deep Dive plans." unless @selection&.status == "finalized"

      @tasks = @selection.snapshot.fetch("final_selection").fetch("tasks")
    end

    def index
      plans = scope.index_by(&:task_key)
      { selection_version: @selection.version, tasks: @tasks.map { |task| summary(task, plans[task.fetch("id")]) } }
    end

    def read(key, version = nil)
      task = task!(key)
      plan = scope.find_by(task_key: key)
      latest = plan&.latest_revision
      revision = version.present? ? (plan || raise(ActiveRecord::RecordNotFound)).revisions.find_by!(version: version) : latest
      summary(task, plan).merge(
        context: plan&.context, version: revision&.version, latest_version: latest&.version, content: revision&.content,
        approved_version: plan&.approved_revision&.version, generation_error: plan&.generation_error,
        history: plan ? plan.revisions.order(version: :desc).as_json(only: %i[version action reason consultant_user_id created_at]) : []
      )
    end

    def generate(key)
      task = task!(key)
      plan = token = nil
      @selection.with_lock do
        plan = scope.find_by(task_key: key)
        if plan
          plan.with_lock do
            if plan.status == "failed" || self.class.stale?(plan)
              token = SecureRandom.uuid
              plan.update!(status: "queued", generation_token: token, generation_error: nil)
            end
          end
        else
          token = SecureRandom.uuid
          plan = scope.create!(task_key: key, status: "queued", generation_token: token,
                               context: Context.new(@run, @selection, task).call)
        end
      end
      enqueue(plan, token) if token
      read(key)
    end

    def revise(key, command, approve: false)
      task!(key)
      plan = scope.find_by!(task_key: key)
      plan.with_lock do
        raise Conflict, "An approved plan is locked." if plan.status == "approved"
        raise Conflict, "Generate a draft before editing or approving." unless plan.status == "draft"

        latest = plan.latest_revision
        raise Conflict, "A newer plan version exists. Reload it before continuing." unless command["expected_version"] == latest.version

        reason = Content.text(command["reason"], "Decision reason", 2_000)
        content = approve ? latest.content : Content.new(plan.context).validate(command["content"])
        plan.revisions.create!(version: latest.version + 1, action: approve ? "approved" : "edited",
                               consultant_user: @actor, reason: reason, content: content)
        plan.update!(status: "approved") if approve
      end
      read(key)
    end

    def self.stale?(plan)
      plan.status.in?(%w[queued generating]) && plan.updated_at <= STALE_AFTER.ago
    end

    private

    def task!(key)
      @tasks.find { |task| task["id"] == key } || raise(ActiveRecord::RecordNotFound)
    end

    def scope
      DeepDivePlan.where(task_selection_revision: @selection)
    end

    def summary(task, plan)
      { task_id: task.fetch("id"), title: task.fetch("title"), status: plan&.status || "not_started",
        retry_available: !!(plan && (plan.status == "failed" || self.class.stale?(plan))) }
    end

    def enqueue(plan, token)
      return if GenerateDeepDivePlanJob.perform_later(plan.id, token, @actor.id)

      GenerateDeepDivePlanJob.fail_attempt(plan, token, "Plan generation could not be queued. Try again.")
    rescue ActiveJob::EnqueueError, Redis::BaseError
      GenerateDeepDivePlanJob.fail_attempt(plan, token, "Plan generation could not be queued. Try again.")
    end
  end
end
