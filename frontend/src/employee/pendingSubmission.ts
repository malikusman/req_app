export type PendingSubmission = { id: string; body: string; file?: File; rejected?: boolean };

function database(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('mjadi-discovery-recovery', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('submissions');
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export async function pendingSubmission(link: string, value?: PendingSubmission | null): Promise<PendingSubmission | null> {
  const db = await database();
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction('submissions', value === undefined ? 'readonly' : 'readwrite');
      const store = tx.objectStore('submissions');
      const request = value === undefined ? store.get(link) : value === null ? store.delete(link) : store.put(value, link);
      tx.oncomplete = () => resolve(value === undefined ? request.result || null : value);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  } finally { db.close(); }
}
