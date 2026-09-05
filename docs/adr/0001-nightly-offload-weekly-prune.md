# Nightly offload with weekly local Prune

We dump the database nightly, Offload each Backup to S3 the same night, and Prune local Backups only once a week. Archives never expire: a bucket lifecycle rule transitions them to Deep Archive after 30 days, but they are never deleted.

We considered Offloading in a single weekly batch as first proposed, but accepted that bulk-weekly leaves up to a week of Backups existing only on local disk — the least durable copy. A nightly offload is effectively free (Backups are ~MB) and closes that data-loss window. The local store is still kept lean by a weekly Prune, which never touches a Backup that has not been confirmed as an Archive, and which re-Offloads any stragglers before deciding what to delete.