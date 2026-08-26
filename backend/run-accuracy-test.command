#!/bin/zsh
# Double-clickable accuracy test for the PortL analyst.
# First run: asks for the Anthropic API key once and saves it to backend/.env
# (which is gitignored, so it never leaves this machine). Every run after
# that: no typing at all.

cd "$(dirname "$0")"

if ! grep -q "^ANTHROPIC_API_KEY=sk" .env 2>/dev/null; then
  echo "One-time setup — paste your Anthropic API key and press Return."
  echo "(Nothing will appear while you paste. It is saved only to backend/.env on this Mac.)"
  read -s "KEY?Key: "
  echo
  if [[ -z "$KEY" ]]; then
    echo "No key entered. Exiting."
    exit 1
  fi
  # Preserve any other settings already in .env; replace only this key.
  touch .env
  grep -v "^ANTHROPIC_API_KEY=" .env > .env.tmp 2>/dev/null || true
  echo "ANTHROPIC_API_KEY=$KEY" >> .env.tmp
  mv .env.tmp .env
  chmod 600 .env
  echo "Saved. You will not be asked again."
  echo
fi

echo "Running accuracy test (takes 1-2 minutes)..."
echo
npm run --silent accuracy
STATUS=$?

echo
if [[ $STATUS -eq 0 ]]; then
  echo "Done. You can close this window."
else
  echo "The test reported failures (see above). You can close this window."
fi
