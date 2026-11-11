update storage.buckets
set allowed_mime_types = array[
  'text/html',
  'text/css',
  'text/javascript',
  'application/javascript',
  'application/manifest+json',
  'application/json',
  'image/png',
  'application/vnd.android.package-archive'
]
where id = 'task-buddy-mobile';

create policy "Temporary Task Buddy Android upload"
  on storage.objects for insert
  to anon
  with check (
    bucket_id = 'task-buddy-mobile'
    and name = 'TaskBuddy-Android.apk'
  );
