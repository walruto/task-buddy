create policy "Temporary Task Buddy notification APK read"
  on storage.objects for select
  to anon
  using (bucket_id = 'task-buddy-mobile' and name = 'TaskBuddy-Android.apk');

create policy "Temporary Task Buddy notification APK insert"
  on storage.objects for insert
  to anon
  with check (bucket_id = 'task-buddy-mobile' and name = 'TaskBuddy-Android.apk');

create policy "Temporary Task Buddy notification APK update"
  on storage.objects for update
  to anon
  using (bucket_id = 'task-buddy-mobile' and name = 'TaskBuddy-Android.apk')
  with check (bucket_id = 'task-buddy-mobile' and name = 'TaskBuddy-Android.apk');
