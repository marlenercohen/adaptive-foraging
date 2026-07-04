class StimulusRegistry {
  constructor(entries = null) {
    this.entries = entries || {
      emoji: {
        name: 'emoji',
        displayName: 'Emoji',
        description: 'Unicode emoji stimulus set',
        version: '1.0',
        imageDirectory: 'images/',
        metadataFile: 'stimuli/emoji/metadata.json'
      }
    };
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
    if (!entry.name || typeof entry.name !== 'string') {
      throw new Error(`Stimulus set "${setName}" is missing required field "name".`);
    }
    if (!entry.displayName || typeof entry.displayName !== 'string') {
      throw new Error(`Stimulus set "${setName}" is missing required field "displayName".`);
    }
    if (!entry.metadataFile || typeof entry.metadataFile !== 'string') {
      throw new Error(`Stimulus set "${setName}" is missing required field "metadataFile".`);
    }
    if (!entry.imageDirectory || typeof entry.imageDirectory !== 'string') {
      throw new Error(`Stimulus set "${setName}" is missing required field "imageDirectory".`);
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
    const rawEntry = this.getEntry(setName);
    const entry = {
      name: setName,
      displayName: setName,
      description: '',
      version: '1.0',
      ...rawEntry
    };
    this.validateEntry(setName, entry);

    let response;
    try {
      response = await fetch(entry.metadataFile);
    } catch (error) {
      throw new Error(`Failed to fetch metadata for stimulus set "${setName}" from ${entry.metadataFile}: ${error?.message || String(error)}`);
    }

    if (!response.ok) {
      throw new Error(`Metadata file for stimulus set "${setName}" could not be loaded from ${entry.metadataFile} (HTTP ${response.status}).`);
    }

    let data;
    try {
      data = await response.json();
    } catch (error) {
      throw new Error(`Metadata file for stimulus set "${setName}" is not valid JSON: ${error?.message || String(error)}`);
    }

    this.validateMetadataRows(setName, data);

    return {
      ...entry,
      key: setName
    };
  }
}

window.StimulusRegistry = StimulusRegistry;