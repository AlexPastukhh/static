#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/results/baseline"

echo "== Python =="
(
  cd "$ROOT/python-lab" &&
  python3 -m lab.main
) | tee "$ROOT/results/baseline/python.txt"

echo
echo "== Java =="
(
  cd "$ROOT/java-lab"
  rm -rf out
  mkdir -p out
  find src/main/java -name '*.java' -print0 | xargs -0 javac -d out
  java -cp out lab.Main
) | tee "$ROOT/results/baseline/java.txt"

echo
echo "== Node/TypeScript =="
if command -v npm >/dev/null 2>&1; then
  (
    cd "$ROOT/node-lab"
    if command -v tsc >/dev/null 2>&1; then
      tsc -p tsconfig.json
      node dist/main.js
    else
      if [ ! -d node_modules ]; then
        npm install
      fi
      npm run build
      npm start
    fi
  ) | tee "$ROOT/results/baseline/node.txt"
else
  echo "npm not installed; skipped" | tee "$ROOT/results/baseline/node.txt"
fi

echo
echo "== .NET =="
if command -v dotnet >/dev/null 2>&1; then
  (
    cd "$ROOT/dotnet-lab"
    dotnet run
  ) | tee "$ROOT/results/baseline/dotnet.txt"
else
  echo "dotnet not installed; skipped" | tee "$ROOT/results/baseline/dotnet.txt"
fi
