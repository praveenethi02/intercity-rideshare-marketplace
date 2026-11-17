// Brands and models for the add-vehicle dropdowns, by vehicle type.
// These are suggestions only: a driver can choose "Other" and type any make or model, and the
// make and model columns accept any text. Add common Sri Lankan vehicles here as they come up.

const CATALOG = Object.freeze({
  CAR: {
    Toyota: ['Axio', 'Allion', 'Premio', 'Corolla', 'Aqua', 'Prius', 'Vitz', 'Yaris', 'Belta', 'Camry'],
    Suzuki: ['Alto', 'Wagon R', 'Swift', 'Celerio', 'Spresso', 'Dzire', 'Baleno'],
    Honda: ['Fit', 'Grace', 'Civic', 'City', 'Insight', 'Vezel'],
    Nissan: ['Sunny', 'Tiida', 'Leaf', 'March', 'Note', 'Bluebird'],
    Perodua: ['Axia', 'Bezza', 'Myvi'],
    Hyundai: ['Grand i10', 'Accent', 'Elantra'],
    Kia: ['Picanto', 'Rio', 'Cerato'],
    Micro: ['Panda', 'Trend'],
    Mazda: ['Axela', 'Demio', 'Mazda 3'],
    Mitsubishi: ['Lancer', 'Mirage', 'Attrage'],
  },
  SUV: {
    Toyota: ['Land Cruiser Prado', 'Rush', 'RAV4', 'Fortuner', 'C-HR', 'Raize'],
    Honda: ['Vezel', 'CR-V', 'HR-V'],
    Mitsubishi: ['Montero', 'Pajero', 'Outlander', 'Xpander'],
    Nissan: ['X-Trail', 'Kicks', 'Patrol'],
    Suzuki: ['Vitara', 'Grand Vitara', 'Jimny', 'XL7'],
    Kia: ['Sportage', 'Sorento', 'Seltos'],
    Hyundai: ['Tucson', 'Santa Fe', 'Creta'],
    Mahindra: ['Scorpio', 'XUV300', 'XUV500'],
  },
  VAN: {
    Toyota: ['HiAce', 'KDH', 'Noah', 'Voxy', 'Townace'],
    Nissan: ['Caravan', 'Vanette', 'Serena'],
    Suzuki: ['Every', 'APV'],
    Mazda: ['Bongo'],
    Mitsubishi: ['Delica'],
    Hyundai: ['H-1'],
  },
  THREE_WHEELER: {
    Bajaj: ['RE', 'RE 4S', 'Maxima'],
    TVS: ['King', 'King Deluxe'],
    Piaggio: ['Ape City', 'Ape'],
  },
  MOTORBIKE: {
    Honda: ['Dio', 'CD 125', 'Hornet', 'CB Shine', 'Activa'],
    Bajaj: ['Pulsar', 'CT 100', 'Platina', 'Discover', 'Avenger'],
    TVS: ['Apache', 'Ntorq', 'Wego', 'Jupiter', 'Metro'],
    Hero: ['Splendor', 'Pleasure', 'Maestro', 'Hunk', 'Dash'],
    Yamaha: ['FZ', 'Ray ZR', 'Fazer', 'R15', 'Fascino'],
    Suzuki: ['Gixxer', 'Access', 'GN 125'],
  },
  MINIBUS: {
    Toyota: ['Coaster'],
    Mitsubishi: ['Rosa'],
    Nissan: ['Civilian'],
    Isuzu: ['Journey'],
  },
  BUS: {
    'Ashok Leyland': ['Viking', 'Lynx'],
    Tata: ['Starbus', 'LP 1512'],
  },
  PICKUP: {
    Toyota: ['Hilux', 'Townace Truck'],
    Mitsubishi: ['L200', 'Triton'],
    Nissan: ['Navara', 'NP300'],
    Isuzu: ['D-Max'],
    Mahindra: ['Bolero', 'Scorpio Pik Up'],
    Tata: ['Xenon', 'Ace'],
    Ford: ['Ranger'],
  },
  LORRY: {
    Isuzu: ['Elf', 'NPR', 'Forward'],
    Mitsubishi: ['Canter', 'Fuso'],
    Tata: ['LPT 709', 'LPT 1613', 'Ultra'],
    'Ashok Leyland': ['Dost', 'Boss'],
    Toyota: ['Dyna'],
  },
});

/** [{ name, models }] for one vehicle type, brands and models sorted by name. */
function brandsFor(type) {
  return Object.entries(CATALOG[type] || {})
    .map(([name, models]) => ({ name, models: [...models].sort((a, b) => a.localeCompare(b)) }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

module.exports = { CATALOG, brandsFor };
