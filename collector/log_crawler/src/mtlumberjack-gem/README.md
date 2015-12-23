This gem contains the log transport client code for the mt-lumberjack (multi-tenant lumberjack) protocol. It was derived from Jordan Sissel's jls-lumberjack-0.0.20.gem at: https://rubygems.org/gems/jls-lumberjack

Some key modifications made to the original code are:

* New data handshake for the client to send a tenant-id and password over the SSL connection. If authenticated successfully, the session remembers the tenant-id and validates every event-block contains that tenant-id as a tag.
* Implementation of "regular" and "introspection" execution modes. The former is used by regular Logstash users; the latter is used by the log crawler.
* Proper timestamping of log events.
* Support for arrays as values of log record attributes.
* Batching of log events.
