/**
 * ✅ Slot Filler: Replace {slot} placeholders in templates
 */

export interface SlotValues {
  brand?: string | null;
  category?: string | null;
  price?: string | null;
  city?: string | null;
  purpose?: string | null;
  gender?: string | null;
}

/**
 * Fill slots in template string
 */
export function fillSlots(template: string, values: SlotValues): string {
  let result = template;
  
  if (values.brand) {
    result = result.replace(/{brand}/g, values.brand);
  }
  if (values.category) {
    result = result.replace(/{category}/g, values.category);
  }
  if (values.price) {
    result = result.replace(/{price}/g, values.price);
  }
  if (values.city) {
    result = result.replace(/{city}/g, values.city);
  }
  if (values.purpose) {
    result = result.replace(/{purpose}/g, values.purpose);
  }
  if (values.gender) {
    result = result.replace(/{gender}/g, values.gender);
  }
  
  // Remove unfilled slots (optional - could keep them or remove)
  result = result.replace(/{[^}]+}/g, '');
  
  return result.trim();
}

