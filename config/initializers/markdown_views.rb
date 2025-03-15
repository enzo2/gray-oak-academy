# Configure MarkdownViews options
MarkdownViews.strip_comments = false
MarkdownViews.rendering_opts.merge! unsafe: true # Allow HTML in markdown
MarkdownViews.rendering_opts.merge! github_pre_lang: false # Don't wrap code blocks in <pre><code> tags

# Modify the markdown helper to remove triple backticks surrounding executable blocks, as some LLMs cannot help themselves and won't follow instructions
module MarkdownViewsHelper
  def markdown(source = nil)
    if block_given?
      source = capture do
        yield
      end.strip_heredoc
    end

    processed_source = source.gsub(/```[a-zA-Z]*\s*(<pre[^>]*data-executable[^>]*>.*?\/\/EOB\s*<\/pre>)\s*```/m, '\1')

    MarkdownViews::Renderer.render(processed_source).html_safe
  end
end
