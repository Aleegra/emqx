# EMQ X 4.3 Changes

Started tracking changes in CHANGE.md since EMQ X v4.3.11

NOTE: Keep pre-pedning to the head of the file instead of the tail

File format:

- Use weight-2 heading for releases
- One list item per change topic
  Change log ends with a list of github PRs

## v4.3.11

Important notes:

- For Debian/Ubuntu users

  We changed package installed service from init.d to systemd.
  The upgrade from init.d to systemd is verified, however it is
  recommended to verify it before rolling out to production.
  At least to ensure systemd is available in your system.

- For Centos Users

  RPM package now depends on `openssl11` which is NOT available
  in certain centos distributions.
  Please make sure the yum repo [epel-release](https://docs.fedoraproject.org/en-US/epel) is installed.

### Important changes

* Debian/Ubuntu package (deb) installed EMQ X now runs on systemd [#6389]<br>
  This is to take advantage of systemd's supervision functionality to ensure
  EMQ X service is restarted after crash.

* Clustering malfunction fixes [#6221, #6225, #6381]

### Minor changes

* Improved log message when TCP proxy is in use but proxy_protocol configuration is not turned on [#6416]<br>
  "please check proxy_protocol config for specific listeners and zones" to hint a misconfiguration

* Helm chart supports networking.k8s.io/v1 [#6368]

* Fix session takeover race condition which may lead to message loss [#6396]

* EMQ X docker images are pushed to aws public ecr in an automated CI job [#6271]<br>
  `docker pull public.ecr.aws/emqx/emqx:4.3.10`

* Fix webhook URL path to allow rule-engine variable substitution [#6399]

* Corrected RAM usage display [#6379]

* Changed emqx_sn_registry table creation to runtime [#6357]<br>
  This was a bug introduced in 4.3.3, in whihch the table is changed from ets to mnesia<br>
  this will cause upgrade to fail when a later version node joins a 4.3.0-2 cluster<br>

* Log level for normal termination changed from info to debug [#6358]

* Added config `retainer.stop_publish_clear_msg` to enable/disable empty message retained message publish [#6343]<br>
  In MQTT 3.1.1, it is unclear if a MQTT broker should publish the 'clear' (no payload) message<br>
  to the subscribers, or just delete the retained message. So we have made it configurable

* Fix mqtt bridge malfunction when remote host is unreachable (hangs the connection) [#6286, #6323]

* System monotor now inspects `current_stacktrace` of suspicious process [#6290]<br>
  `current_function` was not quite helpful

* Changed default `max_topc_levels` config value to 128 [#6294, #6420]<br>
  previously it has no limit (config value = 0), which can be a potential DoS threat

* Collect only libcrypto and libtinfo so files for zip package [#6259]<br>
  in 4.3.10 we tried to collect all so files, however glibc is not quite portable

* Added openssl-1.1 to RPM dependency [#6239]

* Http client duplicated header fix [#6195]

* Fix `node_dump` issues when working with deb or rpm installation [#6209]

* Pin Erlang/OTP 23.2.7.2-emqx-3 [#6246]<br>
  4.3.10 is on 23.2.7.2-emqx-2, this bump is to fix an ECC signature name typo:<br>
  ecdsa_secp512r1_sha512 -> ecdsa_secp521r1_sha512

* HTTP client performance improvement [#6474, #6414]<br>
  The changes are mostly done in the dependency [repo](https://github.com/emqx/ehttpc).

* For messages from gateways add message properties as MQTT message headers [#6142]<br>
  e.g. messages from CoAP, LwM2M, Stomp, ExProto, when translated into MQTT message<br>
  properties such as protocol name, protocol version, username (if any) peer-host<br>
  etc. are filled as MQTT message headers.

## v4.3.0~10

Older version changes are not tracked here.
