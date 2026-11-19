# frozen_string_literal: true

require "active_support/file_update_checker"

# Development only. Rails asks its file watchers "did any code change?" at the
# start of every request and every Sidekiq job. On a Windows Docker bind mount
# the stock checker stats every autoloaded file each time (~2-6 s measured), so
# every discovery POST, every poll and every queued turn paid that delay.
#
# This watcher does the same scan on a background thread every INTERVAL seconds
# and answers `updated?` from the latest result, so requests no longer wait on the
# filesystem. Code still reloads automatically, ~INTERVAL + one scan after a save.
# Set RAILS_SYNC_FILE_WATCHER=1 to go back to the stock behaviour.
class BackgroundFileUpdateChecker
  INTERVAL = 1.0

  def initialize(files, dirs = {}, &block)
    @checker = ActiveSupport::FileUpdateChecker.new(files, dirs, &block)
    @mutex = Mutex.new
    @scan = Mutex.new # the stock checker is not thread-safe
    @changed = false
    @thread = Thread.new { poll }
    @thread.name = "file-update-checker"
  end

  def updated?
    @mutex.synchronize { @changed }
  end

  def execute
    @mutex.synchronize { @changed = false }
    @scan.synchronize { @checker.execute }
  end

  def execute_if_updated
    return false unless updated?

    yield if block_given?
    execute
    true
  end

  private

  def poll
    loop do
      sleep INTERVAL
      changed = @scan.synchronize { @checker.updated? }
      @mutex.synchronize { @changed ||= changed } if changed
    rescue StandardError
      # A file vanishing mid-scan is not fatal; the next scan sees the new state.
    end
  end
end
