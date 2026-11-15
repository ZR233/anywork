FROM ubuntu:22.04@sha256:8a2321a92b438238f93b4346fff61bc4259c99fdd4d9b52ee86f153fee0c344f
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY pl-provider-fixture /opt/fixture/pl-provider-fixture
COPY start.sh /opt/fixture/start.sh
WORKDIR /workspace/task
ENTRYPOINT ["/bin/sh", "/opt/fixture/start.sh"]
CMD ["sleep", "infinity"]
