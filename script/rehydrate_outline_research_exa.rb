# One-off rehydration script for course outline research payloads.
#
# Usage:
#   bin/rails runner script/rehydrate_outline_research_exa.rb
#   bin/rails runner script/rehydrate_outline_research_exa.rb 18
#   bin/rails runner script/rehydrate_outline_research_exa.rb --course=18 --dry-run
#
# This fetches the current Exa research result by stored research id and rewrites
# Course#outline_research using EnrichCourseOutlineJob's extraction/normalization.

course_id = 18
dry_run = false

ARGV.each do |arg|
  case arg
  when /\A\d+\z/
    course_id = arg.to_i
  when /\A--course=(\d+)\z/
    course_id = Regexp.last_match(1).to_i
  when "--dry-run"
    dry_run = true
  end
end

raise "Invalid course id: #{course_id.inspect}" if course_id <= 0

course = Course.find(course_id)
existing = course.outline_research_hash.deep_dup
research_id = existing.dig("exa_research", "research_id").to_s.presence || existing["research_id"].to_s.presence
raise "No research_id found in course outline_research for course #{course.id}" if research_id.blank?
raise "Course #{course.id} has no teacher; cannot authorize Exa request." unless course.teacher

puts "Rehydrating outline research for course #{course.id} (#{course.title}) with Exa research id #{research_id}..."

exa = ExaApiService.new(current_user: course.teacher)
response = exa.get_research(research_id: research_id)
status = response["status"].to_s.downcase
raise "Exa research status is '#{status.presence || 'unknown'}' (expected completed)." unless status == "completed"

job = EnrichCourseOutlineJob.new
raw_payload = job.send(:extract_research_output, response)
normalized = job.send(:normalize_outline_research, raw_payload)

poll_count = existing.dig("exa_research", "poll_count").to_i
hydrated = normalized.merge(
  "research_id" => research_id,
  "generated_at" => Time.current.iso8601,
  "exa_research" => job.send(
    :exa_research_meta,
    research_id: research_id,
    started_at: existing.dig("exa_research", "started_at"),
    poll_count: poll_count,
    response: response
  )
)

puts "Extracted payload:"
puts "  source_anchors=#{Array(hydrated["source_anchors"]).size}"
puts "  coverage_gaps=#{Array(hydrated["coverage_gaps"]).size}"
puts "  factual_notes=#{Array(hydrated["factual_notes"]).size}"
puts "  alternative_approaches=#{Array(hydrated["alternative_approaches"]).size}"

if dry_run
  puts "Dry run complete. No database changes written."
else
  course.update!(outline_research: hydrated)
  puts "Updated course #{course.id} outline_research successfully."
end
