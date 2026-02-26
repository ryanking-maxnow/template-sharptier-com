# AGENTS.md for /home/template-sharptier-cms

## Mandatory Skills And Docs
All engineering work in this directory must use local `skills/` and `docs/` first.

### Skills path
- `/home/template-sharptier-cms/skills/astro/SKILL.md`
- `/home/template-sharptier-cms/skills/docker/SKILL.md`
- `/home/template-sharptier-cms/skills/nextjs/SKILL.md`
- `/home/template-sharptier-cms/skills/nginx/SKILL.md`
- `/home/template-sharptier-cms/skills/nodejs/SKILL.md`
- `/home/template-sharptier-cms/skills/payloadcms/SKILL.md`
- `/home/template-sharptier-cms/skills/pm2/SKILL.md`
- `/home/template-sharptier-cms/skills/postgresql/SKILL.md`
- `/home/template-sharptier-cms/skills/tailwind-css/SKILL.md`
- `/home/template-sharptier-cms/skills/.system/skill-creator/SKILL.md`
- `/home/template-sharptier-cms/skills/.system/skill-installer/SKILL.md`

### Docs path
- `/home/template-sharptier-cms/docs/project/`
- `/home/template-sharptier-cms/docs/component-docs/nginx-docs/`
- `/home/template-sharptier-cms/docs/component-docs/postgresql-docs/`
- `/home/template-sharptier-cms/docs/component-docs/payload-docs/`

## Trigger Rules
If task matches a skill domain, read corresponding `SKILL.md` before implementation.

- PayloadCMS/collections/hooks/migrations: use `payloadcms`
- Next.js runtime/routes/revalidation: use `nextjs`
- PostgreSQL/database/migration/backup: use `postgresql`
- Nginx/reverse proxy/SSL/cache: use `nginx`
- PM2/process/reload/logging: use `pm2`
- Node runtime/perf/memory: use `nodejs`
- Docker/compose/containerized workflow: use `docker`
- Tailwind UI styling: use `tailwind-css`
- Astro work (if any future frontend split): use `astro`

## Workflow Gate
1. Announce selected skill(s) and docs for the task.
2. Read only required `SKILL.md`/doc files.
3. Implement changes.
4. In summary, list which skills/docs were used.

If this gate is not satisfied, do not mark the engineering task as complete.
