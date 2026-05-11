/**
 * Minimal typed event emitter. Zero dependencies.
 * Usage:
 *   const ee = new Emitter<{ foo: { bar: number } }>();
 *   ee.on('foo', ({ bar }) => console.log(bar));
 *   ee.emit('foo', { bar: 42 });
 */

type Listener<T> = (data: T) => void;

export class Emitter<Events extends Record<string, any>> {
  private listeners = new Map<keyof Events, Set<Listener<any>>>();

  on<K extends keyof Events>(event: K, listener: Listener<Events[K]>): () => void {
    let set = this.listeners.get(event);
    if (!set) {
      set = new Set();
      this.listeners.set(event, set);
    }
    set.add(listener);
    return () => set!.delete(listener);
  }

  once<K extends keyof Events>(event: K, listener: Listener<Events[K]>): () => void {
    const off = this.on(event, (data) => {
      off();
      listener(data);
    });
    return off;
  }

  off<K extends keyof Events>(event: K, listener: Listener<Events[K]>): void {
    this.listeners.get(event)?.delete(listener);
  }

  emit<K extends keyof Events>(event: K, data: Events[K]): void {
    this.listeners.get(event)?.forEach((fn) => {
      try {
        fn(data);
      } catch {
        // Swallow listener errors — don't break emitter
      }
    });
  }

  removeAllListeners(event?: keyof Events): void {
    if (event) {
      this.listeners.delete(event);
    } else {
      this.listeners.clear();
    }
  }
}
