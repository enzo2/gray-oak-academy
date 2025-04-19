# Configure MarkdownViews options
MarkdownViews.strip_comments = false
MarkdownViews.rendering_opts.merge! unsafe: true # Allow HTML in markdown
MarkdownViews.rendering_opts.merge! github_pre_lang: false # Don't wrap code blocks in <pre><code> tags. This is handled by markdown_views.
MarkdownViews.extensions.merge! tagfilter: false # Disable tagfilter extension that blocks certain HTML tags

# Customize the markdown helper.
module MarkdownViewsHelper
  def markdown(source = nil)
    if block_given?
      source = capture do
        yield
      end.strip_heredoc
    end

    # Processor for executable JS blocks.
    # Regex finds all markdown code blocks with optional attributes.
    # LLM is instructed on adding attributes in the prompt.
    processed_source = source.gsub(/```(\w+)?\s*(\{.*?\})?\s*\n(.*?)\n^```\s*$/m) do |match|
      # Rails.logger.debug "Processing code block. language: #{$1}, attributes: #{$2}, code: #{$3}"
      language = $1
      attributes_str = $2
      code = $3

      attributes = {}
      if attributes_str
        # Simple parsing for key="value" pairs within {}
        attributes_str.scan(/(\w+)\s*=\s*"([^"]*)"/) do |key, value|
          attributes[key.to_sym] = value
        end
      end

      # Process executable blocks.
      if attributes[:executable] == "true" && language == "javascript"
        Rails.logger.debug "Found executable JS block. Attributes: #{attributes.inspect}"
        # Extract config with defaults
        hidden = attributes.fetch(:hidden, "true") == "true"
        auto_run = attributes.fetch(:autoRun, "false") == "true"
        render_target = attributes.fetch(:renderTarget, "chalkboard")

        # Prepare the block for the Stimulus controller.
        wrapper_attrs = "data-controller=\"code-executor\" " +
                        "data-code-executor-render-target-value=\"#{render_target}\" " +
                        "data-code-executor-auto-run-value=\"#{auto_run}\" " +
                        "data-code-executor-hidden-value=\"#{hidden}\""

        # Render the code block for display. MarkdownViews will apply syntax highlighting with Rouge.
        highlighted_html = MarkdownViews::Renderer.render("```#{language}\n#{code}\n```")
        # Rails.logger.debug "Highlighted HTML: #{highlighted_html}"

        # Combine into the final HTML structure for this executable block.
        # Include the code block as a hidden <pre> for the Stimulus controller to copy.
        # This entire string will replace the original markdown block in processed_source.
        # Due to CommonMark specs, certain odd line breaks are needed to ensure <pre> tags
        # are treated as a single HTML block by the markdown parser, and not given <p> tags within.
        final_html = <<~HTML
          <div class="my-3" #{wrapper_attrs}>
            <div class="highlighted-code-block" data-code-executor-target="highlightedCode">
            \n<!-- extra line ensures commonmark starts a new HTML block for pre-->
            #{highlighted_html}
            </div>
            \n<!-- extra line ensures commonmark starts a new HTML block for pre-->
            <pre class="hidden" data-code-executor-target="rawCode">#{code}</pre>
            <div class="code-actions mt-1" data-code-executor-target="actionsContainer"></div>
          </div>
        HTML
        # Return the fully formed HTML for this block
        final_html
      else
        # Not executable javascript; return the original match for standard processing by the final render call later
        match
      end
    end
    # End of the executable block processing.

    # Any other fixes for undesired LLM formatting habits can go here.
    # Fix KaTeX block math when LLM adds newlines inside the delimiters.
    processed_source = processed_source.gsub(/\$\$[\s\n]*([^\$]*?)[\s\n]*\$\$/, '$$\1$$')

    # Rails.logger.debug "Processed source: #{processed_source}"

    # Render the potentially modified source.
    # The executable blocks have already been replaced with HTML
    # The non-executable blocks (returned as `match`) are still Markdown and will be rendered now.
    # The final .html_safe call is still needed for the overall result.
    MarkdownViews::Renderer.render(processed_source)
  end
end
