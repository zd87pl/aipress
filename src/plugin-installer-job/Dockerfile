# Use a base image with Python pre-installed
FROM python:3.11-slim

# Set DEBIAN_FRONTEND to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

# Install PHP, necessary PHP extensions, WP-CLI, curl, sudo, and Google Cloud SDK CLI (gcloud)
RUN apt-get update && apt-get install -y --no-install-recommends \
        php-fpm \
        php-mysql \
        php-cli \
        php-curl \
        # php-gd \ # Add common extensions if needed by plugins later
        # php-zip \
        curl \
        sudo \
        gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp

# Install Google Cloud SDK (needed for gcloud auth and potentially other commands)
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get install -y apt-transport-https ca-certificates && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
    apt-get update && apt-get install -y google-cloud-cli

# Set up work directory
WORKDIR /app

# Copy requirements file and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the main application script and helper script
COPY main.py .
COPY install_plugins.sh .
RUN chmod +x install_plugins.sh

# Cloud Run Jobs execute the entrypoint and then exit.
# The main.py script will be executed when the job runs.
ENTRYPOINT ["python", "main.py"]
