require "open3"
require "timeout"
require "tempfile"

# Node-based syntax checker wrapper.
# This service writes the provided code to a temporary file and invokes
# `node --check` to perform a parse-only syntax check using V8's parser.
# It returns a hash of { valid: bool, errors: [messages] }.
#
# Notes:
# - This service assumes `node` is available on PATH (devcontainer / dev machine).
# - The command is run with a short timeout to avoid hangs.
class NodeJsSyntaxChecker
  DEFAULT_TIMEOUT_SEC = 1

  def self.check(code, timeout_sec: DEFAULT_TIMEOUT_SEC)
    return { valid: true, errors: [] } if code.nil? || code.strip.empty?

    # Write code to temp file with .mjs extension to hint module semantics
    file = Tempfile.new([ "applet_check", ".mjs" ])
    begin
      file.write(code)
      file.flush

      # Use simple node --check on the temp file. Node will infer module semantics from .mjs
      cmd = [ "node", "--check", file.path ]

      stdout = ""
      stderr = ""
      status = nil

      begin
        Timeout.timeout(timeout_sec) do
          stdout, stderr, status = Open3.capture3(*cmd)
        end
      rescue Timeout::Error
        return { valid: false, errors: [ "Node syntax check timed out after #{timeout_sec}s" ] }
      end

      # node --check returns non-zero on parse errors; stderr contains the message.
      if status && status.success?
        { valid: true, errors: [] }
      else
        # Normalize stderr into lines and strip noise
        messages = stderr.to_s.lines.map(&:strip).reject(&:empty?)
        messages = [ "Node returned an error during syntax check" ] if messages.empty?
        { valid: false, errors: messages }
      end
    rescue Errno::ENOENT
      { valid: false, errors: [ "Node.js not found on PATH (Errno::ENOENT)" ] }
    rescue => e
      { valid: false, errors: [ "Unexpected error: #{e.class}: #{e.message}" ] }
    ensure
      file.close!
    end
  end
end
