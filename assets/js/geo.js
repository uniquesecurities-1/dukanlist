/* ============================================================
   GEO — Cascading dropdown helpers (State → District → City → Locality)
   Uses Supabase tables: geo_states, geo_districts, geo_cities, geo_localities
   ============================================================ */
(function(global){
  'use strict';

  async function loadStates(){
    const c = ShopDB.client; if (!c) return [];
    const { data, error } = await c.from('geo_states')
      .select('id, code, name, name_hi')
      .eq('active', true)
      .order('sort_order', { ascending: true });
    if (error) { console.error('loadStates', error); return []; }
    return data || [];
  }

  async function loadDistricts(stateId){
    const c = ShopDB.client; if (!c || !stateId) return [];
    const { data, error } = await c.from('geo_districts')
      .select('id, name, name_hi')
      .eq('state_id', stateId)
      .eq('active', true)
      .order('name');
    if (error) { console.error('loadDistricts', error); return []; }
    return data || [];
  }

  async function loadCities(districtId){
    const c = ShopDB.client; if (!c || !districtId) return [];
    const { data, error } = await c.from('geo_cities')
      .select('id, name, name_hi, pincodes')
      .eq('district_id', districtId)
      .eq('active', true)
      .order('name');
    if (error) { console.error('loadCities', error); return []; }
    return data || [];
  }

  async function loadLocalities(cityId){
    const c = ShopDB.client; if (!c || !cityId) return [];
    const { data, error } = await c.from('geo_localities')
      .select('id, name, name_hi, pincode')
      .eq('city_id', cityId)
      .order('name');
    if (error) { console.error('loadLocalities', error); return []; }
    return data || [];
  }

  async function validatePincode(pincode, cityId){
    const c = ShopDB.client; if (!c) return false;
    const { data, error } = await c.rpc('validate_pincode_city', { p_pincode: pincode, p_city_id: cityId });
    if (error) { console.error('validatePincode', error); return false; }
    return !!data;
  }

  // Helper: populate <select> element with options
  function fillSelect(selectEl, items, placeholder, lang){
    lang = lang || 'en';
    selectEl.innerHTML = '<option value="">' + (placeholder || '— select —') + '</option>';
    items.forEach(it => {
      const opt = document.createElement('option');
      opt.value = it.id;
      const primary = (lang === 'hi' && it.name_hi) ? it.name_hi : it.name;
      opt.textContent = primary;
      opt.dataset.pincodes = (it.pincodes || []).join(',');
      selectEl.appendChild(opt);
    });
  }

  // ============================================================
  // Public API
  // ============================================================
  global.Geo = {
    loadStates, loadDistricts, loadCities, loadLocalities,
    validatePincode, fillSelect
  };

})(window);
