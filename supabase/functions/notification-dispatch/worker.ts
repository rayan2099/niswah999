export type PushJob = {job_id: string; lease_id: string; inbox_id: string;
  recipient_id: string; kind: string; target_id: string; device_id: string; token: string; locale: string};
export function messageFor(job: PushJob) {
  if (!['privateMessage', 'communityComment', 'communityLike'].includes(job.kind)) throw new Error('Unsupported activity');
  return {message: {token: job.token,
    notification: {title: job.locale === 'ar' ? 'نِسواه' : 'Niswah',
      body: job.locale === 'ar' ? 'لديكِ تحديث جديد في نِسواه.' : 'You have a new update in Niswah.'},
    data: {type: 'activity', eventId: job.inbox_id, userId: job.recipient_id,
      destination: job.kind === 'privateMessage' ? 'conversation' : 'post', targetId: job.target_id},
    android: {priority: job.kind === 'privateMessage' ? 'high' : 'normal', ttl: '3600s', collapse_key: job.kind,
      notification: {channel_id: 'niswah_reminders', visibility: 'PRIVATE', tag: `${job.kind}:${job.target_id}`}},
    apns: {headers: {'apns-push-type': 'alert', 'apns-priority': job.kind === 'privateMessage' ? '10' : '5',
      'apns-collapse-id': job.target_id}, payload: {aps: {sound: 'default', 'thread-id': job.target_id}}}
  }};
}
export function invalidRegistration(status: number, payload: unknown): boolean {
  if (status !== 404 || !payload || typeof payload !== 'object') return false;
  const error = (payload as {error?: {details?: {errorCode?: string}[]}}).error;
  return error?.details?.some(d => d.errorCode === 'UNREGISTERED') === true;
}
export type DispatchDependencies = {
  claim(): Promise<PushJob[]>;
  current(job: PushJob): Promise<boolean>;
  send(job: PushJob): Promise<{accepted: boolean; invalidToken: boolean}>;
  finish(job: PushJob, accepted: boolean, invalid: boolean): Promise<void>;
};
export async function dispatch(deps: DispatchDependencies) {
  const jobs = await deps.claim();
  let accepted = 0, skipped = 0, failed = 0;
  // Bound concurrency and revalidate each lease immediately before sending.
  for (let start = 0; start < jobs.length; start += 5) {
    await Promise.all(jobs.slice(start, start+5).map(async job => {
      try {
        if (!await deps.current(job)) {skipped++; await deps.finish(job,false,false); return;}
        const result = await deps.send(job);
        await deps.finish(job,result.accepted,result.invalidToken);
        if (result.accepted) accepted++; else failed++;
      } catch {failed++; /* Keep lease for bounded retry; never report acceptance. */}
    }));
  }
  return {claimed: jobs.length, accepted, skipped, failed};
}
export function secretMatches(provided: string, expected: string): boolean {
  const a = new TextEncoder().encode(provided), b = new TextEncoder().encode(expected);
  if (a.length !== b.length || b.length < 32) return false;
  let difference = 0;
  for (let i=0; i<a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}
