namespace Hudson.Selection {
  export interface State {
    selectedLayerId: string | null;
  }

  export function payload(layers: Hudson.Layer[], selectedLayerId: string | null): Hudson.SelectionPayload | null {
    const layer = layers.find((candidate) => candidate.id === selectedLayerId);
    return layer ? attachPayload(layer) : null;
  }

  export function attachPayload(layer: Hudson.Layer): Hudson.SelectionPayload {
    return {
      id: layer.id,
      label: layer.label || layer.text || layer.kind,
      kind: layer.kind,
    };
  }

  export function select(state: State, id: string | null): State {
    return { ...state, selectedLayerId: id };
  }

  export function clear(state: State): State {
    return select(state, null);
  }
}
