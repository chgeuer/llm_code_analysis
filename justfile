clean:
    rm -rf _build
    mix clean

credo:
    mix credo --strict

clean-trailing-whitespace:
    find . -type f \( -name "*.ex" -o -name "*.exs" -o -name "*.md" -o -name "*.livemd" \) -exec sed -i 's/[[:space:]]*$//' {} +

format:
    just clean-trailing-whitespace
    mix format
    mix credo --strict

iex:
    iex -S mix

test:
    mix test
