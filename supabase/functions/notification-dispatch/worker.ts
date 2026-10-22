export type PushJob = {job_id: string; lease_id: string; inbox_id: string;
  recipient_id: string; kind: string; target_id: string; device_id: string; token: string; locale: string};
// Discreet lock-screen copy: the kind of activity only, never a name, message
// text or health detail. The app's inbox titles use the same wording.
const copy: Record<string, {ar: string; en: string}> = {
  privateMessage: {ar: 'لديكِ رسالة جديدة في نِسواه.', en: 'You have a new message in Niswah.'},
  communityComment: {ar: 'تعليق جديد على منشوركِ.', en: 'New comment on your post.'},
  communityLike: {ar: 'تفاعل جديد مع منشوركِ.', en: 'New activity on your post.'},
};
export const pushTtlSeconds = 3600;
export function messageFor(job: PushJob, now = Date.now()) {
  const text = copy[job.kind];
  if (!text) throw new Error('Unsupported activity');
  const ar = job.locale === 'ar';
  return {message: {fid: job.token,
    notification: {title: ar ? 'نِسواه' : 'Niswah', body: ar ? text.ar : text.en},
    data: {type: 'activity', eventId: job.inbox_id, userId: job.recipient_id,
      destination: job.kind === 'privateMessage' ? 'conversation' : 'post', targetId: job.target_id},
    android: {priority: job.kind === 'privateMessage' ? 'high' : 'normal', ttl: `${pushTtlSeconds}s`, collapse_key: job.kind,
      notification: {channel_id: 'niswah_activity', visibility: 'PRIVATE', tag: `${job.kind}:${job.target_id}`}},
    // APNs otherwise stores an undeliverable alert for weeks; match Android.
    apns: {headers: {'apns-push-type': 'alert', 'apns-priority': job.kind === 'privateMessage' ? '10' : '5',
      'apns-collapse-id': job.target_id, 'apns-expiration': String(Math.floor(now/1000)+pushTtlSeconds)},
      payload: {aps: {sound: 'default', 'thread-id': job.target_id}}}
  }};
}
export function invalidRegistration(status: number, payload: unknown): boolean {
  if (status !== 404 || !payload || typeof payload !== 'object') return false;
  const error = (payload as {error?: {details?: {errorCode?: string}[]}}).error;
  return error?.details?.some(d => d.errorCode === 'UNREGISTERED') === true;
}
export const batchSize = 50;
export type DispatchDependencies = {
  claim(): Promise<PushJob[]>;
  current(job: PushJob): Promise<boolean>;
  send(job: PushJob): Promise<{accepted: boolean; invalidToken: boolean}>;
  finish(job: PushJob, accepted: boolean, invalid: boolean): Promise<void>;
};
export async function dispatch(deps: DispatchDependencies, options: {budgetMs?: number; maxRounds?: number; now?: () => number} = {}) {
  const now = options.now ?? Date.now, deadline = now() + (options.budgetMs ?? 40000);
  let claimed = 0, accepted = 0, skipped = 0, failed = 0, deferred = 0;
  // Drain backlog in bounded rounds instead of one batch per scheduled minute.
  // Stop claiming before the two-minute lease or the caller's timeout can lapse.
  for (let round = 0; round < (options.maxRounds ?? 5) && now() < deadline; round++) {
    const jobs = await deps.claim();
    claimed += jobs.length;
    // Bound concurrency and revalidate each lease immediately before sending.
    for (let start = 0; start < jobs.length; start += 5) {
      // Unstarted jobs keep their lease and are reclaimed after it expires.
      if (now() >= deadline + 15000) {deferred += jobs.length-start; break;}
      await Promise.all(jobs.slice(start, start+5).map(async job => {
        try {
          if (!await deps.current(job)) {skipped++; await deps.finish(job,false,false); return;}
          const result = await deps.send(job);
          await deps.finish(job,result.accepted,result.invalidToken);
          if (result.accepted) accepted++; else failed++;
        } catch {failed++; /* Keep lease for bounded retry; never report acceptance. */}
      }));
    }
    if (jobs.length < batchSize) break;
  }
  return {claimed, accepted, skipped, failed, deferred};
}
export function secretMatches(provided: string, expected: string): boolean {
  const a = new TextEncoder().encode(provided), b = new TextEncoder().encode(expected);
  if (a.length !== b.length || b.length < 32) return false;
  let difference = 0;
  for (let i=0; i<a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}
