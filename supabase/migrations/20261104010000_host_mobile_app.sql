insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'task-buddy-mobile',
  'task-buddy-mobile',
  true,
  1048576,
  array[
    'text/html',
    'text/css',
    'text/javascript',
    'application/javascript',
    'application/manifest+json',
    'application/json',
    'image/png'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Temporary Task Buddy mobile upload"
  on storage.objects for insert
  to anon
  with check (
    bucket_id = 'task-buddy-mobile'
    and name in (
      'index.html',
      'styles.css',
      'app.js',
      'config.js',
      'manifest.webmanifest',
      'sw.js',
      'icon-256.png'
    )
  );
