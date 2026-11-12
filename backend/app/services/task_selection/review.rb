# frozen_string_literal: true

module TaskSelection
  class Review
    class Invalid < StandardError; end
    class Conflict < StandardError; end

    def initialize(run)
      @run = run
    end

    def read(version = nil)
      review = TaskSelectionReview.find_by(task_intelligence_run: @run)
      head = review&.revisions&.order(version: :desc)&.first
      revision = if version.nil?
                   head
                 elsif version.to_s == "0"
                   nil
                 else
                   raise ActiveRecord::RecordNotFound unless review && version.to_s.match?(/\A[1-9]\d*\z/)

                   review.revisions.find_by!(version: version)
                 end
      {
        run: @run.as_json(only: %i[id version evaluation_mode]),
        version: revision&.version || 0, latest_version: head&.version || 0,
        status: revision&.status || "draft", latest_status: head&.status || "draft",
        snapshot: revision&.snapshot || initial_snapshot,
        history: review ? review.revisions.order(version: :desc).as_json(only: %i[version action reason status consultant_user_id created_at]) : [],
        proposals: evidence.proposals, sources: evidence.sources.values,
        relationships: evidence.relationships, eligible_participants: evidence.participants
      }
    end

    def apply(command, actor:)
      @run.with_lock do
        review = TaskSelectionReview.find_or_create_by!(company_id: @run.company_id, task_intelligence_run: @run)
        head = review.revisions.order(version: :desc).first
        version = head&.version || 0
        raise Conflict, "A newer review revision exists. Reload before saving." unless command["expected_version"] == version
        raise Conflict, "This review has already been finalized." if head&.status == "finalized"

        action = command["action"]
        reason = command["reason"]
        if action == "participants" && (reason.nil? || (reason.is_a?(String) && reason.strip.empty?))
          reason = "Updated interview participants."
        end
        reason = required_text(reason, "Decision reason", 2_000)
        snapshot = head&.snapshot&.deep_dup || initial_snapshot
        apply_action(snapshot, command, action, reason)
        update_summary(snapshot)
        if action == "finalize"
          snapshot["final_selection"] = final_selection(snapshot)
        end
        review.revisions.create!(version: version + 1, consultant_user: actor, action: action, reason: reason,
                                 status: action == "finalize" ? "finalized" : "draft", snapshot: snapshot)
      end
    end

    private

    def evidence
      @evidence ||= Evidence.new(@run)
    end

    def initial_snapshot
      tasks = evidence.proposals.map do |proposal|
        new_task(proposal["title"], proposal["source_ids"], [proposal["id"]], id: "proposal-#{proposal['id']}")
      end
      { "tasks" => tasks, "selected_order" => [], "relationship_overrides" => {}, "capacity_slots" => nil }.tap do |snapshot|
        update_summary(snapshot)
      end
    end

    def new_task(title, ids, proposals, id: SecureRandom.uuid, origins: [])
      { "id" => id, "title" => title, "source_ids" => ids, "proposal_ids" => proposals,
        "origin_task_ids" => origins, "status" => "pending", "participant_ids" => [],
        "notes" => [], "effort_assumptions" => {} }
    end

    def apply_action(snapshot, command, action, reason)
      case action
      when "select", "reject", "defer", "annotate", "participants", "effort"
        update_task(snapshot, command, action, reason)
      when "add"
        ids = source_ids(command["source_ids"], evidence.sources.keys)
        snapshot["tasks"] << new_task(required_text(command["title"], "Title", 255), ids, []).merge("decision_reason" => reason)
      when "merge"
        merge_tasks(snapshot, command, reason)
      when "split"
        split_task(snapshot, command, reason)
      when "reorder"
        order = command["task_ids"]
        expected = snapshot["selected_order"]
        unless order.is_a?(Array) && order.size == expected.size && (order - expected).empty? && order.uniq == order
          raise Invalid, "Reordering must include every selected task exactly once."
        end

        snapshot["selected_order"] = order
      when "relationship"
        ids = source_ids(command["source_ids"], evidence.sources.keys).sort
        classification = command["classification"]
        raise Invalid, "Choose two sources and a valid classification." unless ids.size == 2 && Evidence::CLASSIFICATIONS.include?(classification)

        snapshot["relationship_overrides"][ids.join(":")] = {
          "source_ids" => ids, "classification" => classification, "reason" => reason, "basis" => "consultant_judgment"
        }
      when "capacity"
        slots = command["slots"]
        raise Invalid, "Capacity must be a whole number between 0 and 1,000." unless slots.nil? || (slots.is_a?(Integer) && slots.between?(0, 1_000))

        snapshot["capacity_slots"] = slots
      when "finalize"
        raise Invalid, "Select at least one task before finalizing." if snapshot["selected_order"].empty?

        selected_tasks(snapshot).each { |task| participant_ids(task["participant_ids"], task) }
      else
        raise Invalid, "Unknown review action."
      end
    end

    def update_task(snapshot, command, action, reason)
      task = active_task(snapshot, command["task_id"])
      case action
      when "annotate"
        task["notes"] << reason
      when "participants"
        task["participant_ids"] = participant_ids(command["participant_ids"], task)
        task["participant_reason"] = reason
      when "effort"
        source_id = command["source_id"]
        raise Invalid, "Choose a source linked to the task." unless task["source_ids"].include?(source_id)

        if command["effort_type"] == "reported"
          task["effort_assumptions"].delete(source_id.to_s)
        else
          task["effort_assumptions"][source_id.to_s] = effort_assumption(command, reason)
        end
      else
        status = { "select" => "selected", "reject" => "rejected", "defer" => "deferred" }.fetch(action)
        task.merge!("status" => status, "decision_reason" => reason)
        if status == "selected"
          snapshot["selected_order"] |= [task["id"]]
        else
          snapshot["selected_order"].delete(task["id"])
        end
      end
    end

    def active_task(snapshot, id)
      task = snapshot["tasks"].find { |row| row["id"] == id }
      raise Invalid, "Choose a current task in this review." unless task && !task["status"].in?(%w[merged split])

      task
    end

    def merge_tasks(snapshot, command, reason)
      ids = command["task_ids"]
      raise Invalid, "Choose at least two distinct tasks to merge." unless ids.is_a?(Array) && ids.size >= 2 && ids == ids.uniq

      originals = ids.map { |id| active_task(snapshot, id) }
      title = required_text(command["title"], "Merged title", 255)
      sources = originals.flat_map { |task| task["source_ids"] }.uniq
      proposals = originals.flat_map { |task| task["proposal_ids"] }.uniq
      snapshot["tasks"] << new_task(title, sources, proposals, origins: ids).merge("decision_reason" => reason)
      originals.each { |task| retire_task(snapshot, task, "merged", reason) }
    end

    def split_task(snapshot, command, reason)
      original = active_task(snapshot, command["task_id"])
      children = command["children"]
      unless children.is_a?(Array) && children.size.between?(2, 20) && children.all? { |child| child.is_a?(Hash) }
        raise Invalid, "Provide between two and twenty child scopes."
      end

      tasks = children.map do |child|
        ids = source_ids(child["source_ids"], original["source_ids"])
        title = required_text(child["title"], "Child title", 255)
        new_task(title, ids, original["proposal_ids"], origins: [original["id"]]).merge("decision_reason" => reason)
      end
      if tasks.flat_map { |task| task["source_ids"] }.uniq.sort != original["source_ids"].sort
        raise Invalid, "The split must preserve every original source across the child tasks."
      end

      retire_task(snapshot, original, "split", reason)
      snapshot["tasks"].concat(tasks)
    end

    def retire_task(snapshot, task, status, reason)
      task.merge!("status" => status, "replacement_reason" => reason)
      snapshot["selected_order"].delete(task["id"])
    end

    def source_ids(ids, allowed)
      unless ids.is_a?(Array) && ids.all? { |id| id.is_a?(Integer) && allowed.include?(id) } && ids == ids.uniq
        raise Invalid, "Sources must be distinct and belong to this evidence scope."
      end

      ids
    end

    def participant_ids(ids, task)
      unless ids.is_a?(Array) && ids.all? { |id| id.is_a?(Integer) } && ids == ids.uniq &&
             (ids - evidence.participants_for(task).pluck("id")).empty?
        raise Invalid, "Choose eligible employees with Discovery evidence linked to this task."
      end

      ids
    end

    def effort_assumption(command, reason)
      type = command["effort_type"]
      unless %w[active waiting unknown].include?(type)
        raise Invalid, "Choose active work, waiting, or unknown effort."
      end

      assumption = { "effort_type" => type, "reason" => reason, "basis" => "consultant_judgment" }
      return assumption if type == "unknown"

      frequency = effort_range(command["frequency"], Findings::AnnualHours::OCCURRENCES_PER_YEAR)
      duration = effort_range(command["duration"], Findings::AnnualHours::MINUTES)
      hours = Findings::AnnualHours.call(
        frequency_min: frequency["min"], frequency_max: frequency["max"], frequency_unit: frequency["unit"],
        duration_min: duration["min"], duration_max: duration["max"], duration_unit: duration["unit"], effort_type: type
      )
      assumption.merge("frequency" => frequency, "duration" => duration, "annual_hours_min" => hours.min,
                       "annual_hours_max" => hours.max, "calculation_basis" => hours.basis, "calculation_reason" => hours.reason)
    end

    def effort_range(value, units)
      unless value.is_a?(Hash) && units.key?(value["unit"]) && %w[min max].all? do |key|
        number = value[key]
        number.is_a?(Numeric) && number.finite? && number.positive? && number <= 1_000_000
      end
        raise Invalid, "Provide positive finite lower and upper values and a valid unit."
      end
      raise Invalid, "The lower effort bound must not exceed the upper bound." if value["min"] > value["max"]

      value.slice("min", "max", "unit")
    end

    def required_text(value, label, max)
      raise Invalid, "#{label} is required and must be at most #{max} characters." unless value.is_a?(String) && value.strip.length.between?(1, max)

      value.strip
    end

    def selected_tasks(snapshot)
      snapshot["selected_order"].map { |id| active_task(snapshot, id) }
    end

    def update_summary(snapshot)
      selected = selected_tasks(snapshot)
      overrides = snapshot["relationship_overrides"]
      snapshot["tasks"].each do |task|
        task["effective_effort"] = evidence.effective_effort(task, selected, overrides)
        task["gaps"] = evidence.gaps(task, selected, overrides)
      end
      ids = selected.flat_map { |task| task["participant_ids"] }
      capacity = snapshot["capacity_slots"]
      gaps = []
      gaps << "Interview capacity has not been recorded." if capacity.nil?
      gaps << "Selected interviews exceed recorded capacity." if capacity && ids.size > capacity
      gaps << "Some employees are selected for multiple tasks. Confirm sampling and availability." if ids.uniq.size < ids.size
      snapshot["sampling"] = { "planned_interviews" => ids.size, "available_slots" => capacity, "gaps" => gaps }
    end

    def final_selection(snapshot)
      selected = selected_tasks(snapshot)
      {
        "task_intelligence_run_id" => @run.id,
        "tasks" => selected.map do |task|
          proposals = evidence.proposals.select do |proposal|
            task["proposal_ids"].include?(proposal["id"]) || task["source_ids"].intersect?(proposal["source_ids"])
          end
          task.merge(
            "source_versions" => task["source_ids"].map { |id| evidence.sources.fetch(id).slice("id", "version", "conversation_id", "employee_id", "discovery_revision") },
            "cluster_revision_ids" => proposals.pluck("process_cluster_revision_id").uniq,
            "clarification_requests" => evidence.relationships.filter_map do |pair|
              pair["clarification_request"] if pair["source_ids"].intersect?(task["source_ids"])
            end.uniq { |request| request["id"] }
          )
        end,
        "relationship_overrides" => snapshot["relationship_overrides"],
        "sampling" => snapshot["sampling"],
        "provisional" => selected.any? { |task| task["gaps"].present? } || snapshot.dig("sampling", "gaps").present?
      }
    end
  end
end
