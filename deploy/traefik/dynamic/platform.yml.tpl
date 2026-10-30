# Rendered by scripts/bootstrap-platform.sh from platform.yml.tpl.
# Do not edit dynamic/platform.yml directly.
http:
  routers:
    traefik-dashboard:
      rule: "Host(`traefik.${DOMAIN}`)"
      entryPoints:
        - websecure
      service: api@internal
      middlewares:
        - dashboard-auth
        - security-headers
        - rate-limit
      tls:
        certResolver: letsencrypt
    uptime-kuma:
      rule: "Host(`monitor.${DOMAIN}`)"
      entryPoints:
        - websecure
      service: uptime-kuma
      middlewares:
        - security-headers
        - rate-limit
      tls:
        certResolver: letsencrypt
    grafana:
      rule: "Host(`grafana.${DOMAIN}`)"
      entryPoints:
        - websecure
      service: grafana
      middlewares:
        - security-headers
        - rate-limit
      tls:
        certResolver: letsencrypt
  services:
    uptime-kuma:
      loadBalancer:
        servers:
          - url: "http://uptime-kuma:3001"
    grafana:
      loadBalancer:
        servers:
          - url: "http://grafana:3000"
  middlewares:
    dashboard-auth:
      basicAuth:
        usersFile: /run/secrets/traefik_dashboard_users
    security-headers:
      headers:
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: strict-origin-when-cross-origin
        permissionsPolicy: "camera=(), microphone=(), geolocation=(), payment=()"
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        forceSTSHeader: true
        customRequestHeaders:
          X-Forwarded-Proto: https
    rate-limit:
      rateLimit:
        average: 50
        burst: 100
        period: 1s

tls:
  options:
    default:
      minVersion: VersionTLS12
      sniStrict: true
