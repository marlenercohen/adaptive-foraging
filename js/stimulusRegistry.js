class StimulusRegistry {
  constructor(entries = null) {
    this.entries = entries || {
      emoji: {
        manifestFile: 'stimuli/emoji/manifest.json'
      }
    };
    this.supportedFeatureTypes = new Set(['boolean', 'categorical', 'continuous']);
  }

  getEntry(setName) {
    return this.entries?.[setName] || null;
  }

  validateEntry(setName, entry) {
    if (!setName || typeof setName !== 'string') {
      throw new Error('Stimulus set name must be a non-empty string.');
    }
    if (!entry) {
      throw new Error(`Stimulus set "${setName}" is not registered.`);
    }
    if (!entry.manifestFile || typeof entry.manifestFile !== 'string') {
      throw new Error(`Stimulus set "${setName}" is missing required field "manifestFile".`);
    }
  }

  validateFeatureSchema(setName, features) {
    if (!Array.isArray(features)) {
      throw new Error(`Stimulus set "${setName}" must define a "features" array.`);
    }

    const featureNames = new Set();
    features.forEach((feature, index) => {
      if (!feature || typeof feature !== 'object') {
        throw new Error(`Feature schema entry ${index} in set "${setName}" must be an object.`);
      }
      if (!feature.name || typeof feature.name !== 'string') {
        throw new Error(`Feature schema entry ${index} in set "${setName}" is missing required field "name".`);
      }
      if (featureNames.has(feature.name)) {
        throw new Error(`Feature schema in set "${setName}" contains duplicate feature name "${feature.name}".`);
      }
      featureNames.add(feature.name);

      if (!feature.displayName || typeof feature.displayName !== 'string') {
        throw new Error(`Feature "${feature.name}" in set "${setName}" is missing required field "displayName".`);
      }

      if (!feature.type || !this.supportedFeatureTypes.has(feature.type)) {
        throw new Error(`Feature "${feature.name}" in set "${setName}" has unsupported type "${feature.type}".`);
      }

      if (feature.type === 'categorical') {
        if (!Array.isArray(feature.values) || feature.values.length === 0) {
          throw new Error(`Categorical feature "${feature.name}" in set "${setName}" must define non-empty "values".`);
        }
      }

      if (feature.type === 'continuous' && feature.units !== undefined && typeof feature.units !== 'string') {
        throw new Error(`Continuous feature "${feature.name}" in set "${setName}" has invalid "units"; expected a string.`);
      }
    });
  }

  validateStimulusSetDefinition(setName, definition) {
    if (!definition || typeof definition !== 'object') {
      throw new Error(`Stimulus set definition for "${setName}" must be an object.`);
    }
    if (!definition.name || typeof definition.name !== 'string') {
      throw new Error(`Stimulus set definition for "${setName}" is missing required field "name".`);
    }
    if (!definition.displayName || typeof definition.displayName !== 'string') {
      throw new Error(`Stimulus set definition for "${setName}" is missing required field "displayName".`);
    }
    if (!definition.metadataFile || typeof definition.metadataFile !== 'string') {
      throw new Error(`Stimulus set definition for "${setName}" is missing required field "metadataFile".`);
    }
    if (!definition.imageDirectory || typeof definition.imageDirectory !== 'string') {
      throw new Error(`Stimulus set definition for "${setName}" is missing required field "imageDirectory".`);
    }
    this.validateFeatureSchema(setName, definition.features);
  }

  async loadJsonOrThrow(path, setName, label) {
    let response;
    try {
      response = await fetch(path);
    } catch (error) {
      throw new Error(`Failed to fetch ${label} for stimulus set "${setName}" from ${path}: ${error?.message || String(error)}`);
    }

    if (!response.ok) {
      throw new Error(`${label.charAt(0).toUpperCase() + label.slice(1)} file for stimulus set "${setName}" could not be loaded from ${path} (HTTP ${response.status}).`);
    }

    try {
      return await response.json();
    } catch (error) {
      throw new Error(`${label.charAt(0).toUpperCase() + label.slice(1)} file for stimulus set "${setName}" is not valid JSON: ${error?.message || String(error)}`);
    }
  }

  validateMetadataRows(setName, rows) {
    if (!Array.isArray(rows)) {
      throw new Error(`Stimulus metadata for set "${setName}" must be an array.`);
    }

    rows.forEach((row, index) => {
      if (!row || typeof row !== 'object') {
        throw new Error(`Stimulus metadata row ${index} in set "${setName}" must be an object.`);
      }
      if (row.id === undefined || row.id === null) {
        throw new Error(`Stimulus metadata row ${index} in set "${setName}" is missing required field "id".`);
      }
      if (typeof row.display !== 'string') {
        throw new Error(`Stimulus metadata row ${index} in set "${setName}" is missing required string field "display".`);
      }
      if (typeof row.features !== 'object' || row.features === null || Array.isArray(row.features)) {
        throw new Error(`Stimulus metadata row ${index} in set "${setName}" is missing required object field "features".`);
      }
    });
  }

  async resolve(setName) {
    const entry = this.getEntry(setName);
    this.validateEntry(setName, entry);

    const manifest = await this.loadJsonOrThrow(entry.manifestFile, setName, 'manifest');
    const definition = {
      name: setName,
      displayName: setName,
      description: '',
      version: '1.0',
      ...manifest
    };
    this.validateStimulusSetDefinition(setName, definition);

    const data = await this.loadJsonOrThrow(definition.metadataFile, setName, 'metadata');

    this.validateMetadataRows(setName, data);

    return {
      ...definition,
      key: setName
    };
  }
}

window.StimulusRegistry = StimulusRegistry;