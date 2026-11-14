#!/bin/sh

git filter-repo --message-callback '
  lines = message.decode("utf-8").splitlines()
  filtered = [l for l in lines if "Generated with" not in l or "Devin" not in l]
  return "\n".join(filtered).encode("utf-8") + b"\n"
' --force

git filter-repo --message-callback '
  import re
  text = message.decode("utf-8")
  lines = [l for l in text.splitlines() if not ("Generated with" in l and "Devin" in l)]
  cleaned = re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()
  return (cleaned + "\n").encode("utf-8")
' --force
