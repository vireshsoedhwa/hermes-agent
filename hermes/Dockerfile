FROM nousresearch/hermes-agent:latest

# System packages (apt)
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     <package-name> \
#     && rm -rf /var/lib/apt/lists/*

# Python packages (pip)
COPY requirements.txt /tmp/requirements.txt
RUN uv pip install --python /opt/hermes/.venv/bin/python -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt
