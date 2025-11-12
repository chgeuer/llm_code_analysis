clean:
    rm -rf _build
    mix clean

credo:
    mix credo --strict
    
format:
    mix format
    mix credo --strict

iex:
    iex -S mix

test:
    mix test
