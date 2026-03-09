set dotenv-load
set shell := ["bash", "-cu"]

LOG_FILE := "/home/dvitto/projects/plezy-apk-extractor/logs/plezy-apk-extractor.log"

# Show available recipes
default:
    @just --list

# Run the extraction script manually
run:
    @bash extract.sh

# Show last known version vs latest upstream
status:
    @echo "Last published : $(cat .last_version 2>/dev/null || echo '(none)')"
    @echo "Latest upstream: $(curl -sf https://api.github.com/repos/edde746/plezy/releases/latest | jq -r '.tag_name')"

# Clear .last_version to force re-processing on next run
reset:
    @rm -f .last_version && echo "Reset: .last_version removed"

# Tail the cron log
logs:
    tail -f {{LOG_FILE}}
