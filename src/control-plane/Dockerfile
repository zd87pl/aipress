# Use an official Python runtime as a parent image
FROM python:3.11-slim-bookworm

LABEL maintainer="AIPress PoC"
LABEL description="Control Plane API for AIPress"

ENV DEBIAN_FRONTEND=noninteractive \
    # Python optimization flags
    PYTHONFAULTHANDLER=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100

# Poetry installation settings (if used, not currently)
# ENV POETRY_VERSION=1.7.1
# ENV POETRY_HOME="/opt/poetry"
# ENV POETRY_VIRTUALENVS_CREATE=false
# ENV PATH="$POETRY_HOME/bin:$PATH"

# Terraform settings
# Specify Terraform version
ENV TERRAFORM_VERSION="1.8.4"

WORKDIR /app

# Install system dependencies including wget and unzip for Terraform
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        unzip \
        # Add any other system dependencies your app might need
    && rm -rf /var/lib/apt/lists/*

# Install Terraform
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    wget "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip"; \
    unzip "terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" -d /usr/local/bin/; \
    rm "terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip"; \
    # Verify installation
    terraform --version

# Copy application code and requirements file
# Since build context is project root, copy relative paths
COPY src/control-plane/requirements.txt requirements.txt
COPY src/control-plane/main.py main.py
# Copy the entire infra directory needed by the control plane to run terraform
COPY infra /infra

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Expose the port the app runs on
EXPOSE 8000

# Command to run the application using uvicorn
# Note: No --reload in production container
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
