export function audit(event: string, payload: Record<string, unknown>) {
  console.info(
    JSON.stringify({
      ts: new Date().toISOString(),
      event,
      ...payload,
    }),
  );
}
