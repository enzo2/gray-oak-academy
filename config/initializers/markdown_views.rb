# Configure MarkdownViews options
# MarkdownViews.strip_comments = false
MarkdownViews.rendering_opts.merge! unsafe: true # Allow HTML in markdown
MarkdownViews.rendering_opts.merge! github_pre_lang: false # Don't wrap code blocks in <pre><code> tags
