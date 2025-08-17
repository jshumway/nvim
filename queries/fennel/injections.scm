; extends

(
    [
        (string_content)
    ] @injection.content
    (#match? @injection.content "^//glsl")
    (#set! injection.language "glsl")
)
