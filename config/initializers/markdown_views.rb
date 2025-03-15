# Configure MarkdownViews options
MarkdownViews.strip_comments = false
MarkdownViews.rendering_opts.merge! unsafe: true # Allow HTML in markdown
MarkdownViews.rendering_opts.merge! github_pre_lang: false # Don't wrap code blocks in <pre><code> tags

# Some LLMs will not follow instructions on formatting. Modify the markdown parser to fix some issues.
module MarkdownViewsHelper
  def markdown(source = nil)
    if block_given?
      source = capture do
        yield
      end.strip_heredoc
    end

    processed_source = source
      # remove triple backticks surrounding executable blocks,
      .gsub(/```[a-zA-Z]*\s*(<pre[^>]*data-executable[^>]*>.*?\/\/EOB\s*<\/pre>)\s*```/m, '\1')
      # remove newlines in block math
      .gsub(/\$\$[\s\n]*([^\$]*?)[\s\n]*\$\$/, '$$\1$$')

    MarkdownViews::Renderer.render(processed_source).html_safe
  end
end
