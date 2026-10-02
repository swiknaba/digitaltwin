# Domains
Each context owns its entities, repositories, and queries under `app/domains/<ctx>/`.
Entities stay private to the owning context; other contexts reference only `Domains::<Ctx>::Dto`.
May reference: its own internals, `Platform`, and `Domains::<Other>::Dto`.
Never references `Adapters` or `Services`.
