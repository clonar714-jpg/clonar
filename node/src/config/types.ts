/**
 * ✅ Config Types
 * Type definitions for configuration management
 */

// Model type - adjust based on your actual Model type
export type Model = {
  key: string;
  name: string;
  [key: string]: any;
};

type BaseUIConfigField = {
  name: string;
  key: string;
  required: boolean;
  description: string;
  scope: 'client' | 'server';
  env?: string;
};

export type StringUIConfigField = BaseUIConfigField & {
  type: 'string';
  placeholder?: string;
  default?: string;
};

type SelectUIConfigFieldOptions = {
  name: string;
  value: string;
};

export type SelectUIConfigField = BaseUIConfigField & {
  type: 'select';
  default?: string;
  options: SelectUIConfigFieldOptions[];
};

export type PasswordUIConfigField = BaseUIConfigField & {
  type: 'password';
  placeholder?: string;
  default?: string;
};

export type TextareaUIConfigField = BaseUIConfigField & {
  type: 'textarea';
  placeholder?: string;
  default?: string;
};

export type SwitchUIConfigField = BaseUIConfigField & {
  type: 'switch';
  default?: boolean;
};

export type UIConfigField =
  | StringUIConfigField
  | SelectUIConfigField
  | PasswordUIConfigField
  | TextareaUIConfigField
  | SwitchUIConfigField;

export type ConfigModelProvider = {
  id: string;
  name: string;
  type: string;
  chatModels: Model[];
  embeddingModels: Model[];
  config: { [key: string]: any };
  hash: string;
};

export type Config = {
  version: number;
  setupComplete: boolean;
  preferences: {
    [key: string]: any;
  };
  personalization: {
    [key: string]: any;
  };
  modelProviders: ConfigModelProvider[];
  search: {
    [key: string]: any;
  };
};

export type EnvMap = {
  [key: string]: {
    fieldKey: string;
    providerKey: string;
  };
};

export type ModelProviderUISection = {
  name: string;
  key: string;
  fields: UIConfigField[];
};

export type UIConfigSections = {
  preferences: UIConfigField[];
  personalization: UIConfigField[];
  modelProviders: ModelProviderUISection[];
  search: UIConfigField[];
};
