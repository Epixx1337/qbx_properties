export const app = $state({
  view: null,
  tab: 'market',
  isRealtor: false,
})

export const shot = $state({
  active: false,
  index: 0,
  total: 0,
  label: '',
  object: '',
  paused: false,
  primary: 'green',
  done: 0,
  skipped: 0,
  failed: 0,
  empty: 0,
  hasImage: false,
  tuned: false,
})

export const furniture = $state({
  categories: {},
  categoryMeta: {},
  category: null,
  cdnMap: null,
  search: '',
  selected: null,
  placing: false,
  freecam: false,
  worldInput: false,
  placed: [],
  mode: 'translate',
  propertyName: '',
  palette: [],
  tint: 0,
  tintSupported: false,
  transform: null,
  gizmo: null,
  gizmoMode: 'translate',
  gizmoSpace: 'camera',
  cart: [],
  cartTotal: 0,
  pickup: false,
  shopEnabled: true,
  exitConfirm: false,
  restorePrompt: null,
})

export const market = $state({
  listings: [],
  sizes: {},
  sizeOrder: [],
  rentIntervals: [],
  types: {},
  gardens: false,
  selected: null,
  bids: [],
  nearbyClients: [],
  config: {
    minPrice: 1000,
    maxPrice: 100000000,
    minIncrement: 1000,
    auctionHours: 72,
    maxAuctionHours: 72,
  },
})

export const creator = $state({
  enabled: false,
  draft: null,
  interior: null,
  anchor: null,
  coords: null,
})

export const realtor = $state({
  interiors: [],
  buildings: [],
  properties: [],
  propertiesTotal: 0,
  propertiesPage: 1,
  propertiesPages: 1,
  building: null,
  floor: 1,
  units: [],
  details: null,
})

export const tablet = $state({
  propertyName: "",
  wallColors: null,
  wallColor: null,
  access: [],
  accessJobs: null,
  isAccessOwner: false,
  apartment: false,
  nearby: [],
  utilities: null,
  upgrades: null,
  isUpgradeOwner: false,
  garageSpots: 0,
  garageLimit: 0,
  rent: null,
  doorcam: null,
  doorcamView: false,
  maintenance: null,
  layouts: null,
  saleAuth: null,
  timecycle: null,
  timecycles: [],
  rentIntervals: [],
})

export const placement = $state({
  active: false,
  prompt: "",
  points: 0,
  zone: false,
  gizmo: false,
  vehicle: false,
  height: null,
  photo: false,
  capture: false,
  flying: false,
  tour: false,
})

export const preview = $state({
  active: false,
  interior: "",
  points: {},
  types: [],
  property: false,
  setup: false,
})

export const creationFormDefaults = () => ({
  name: '',
  price: 50000,
  size: 'medium',
  isRental: false,
  rentInterval: 24,
  listingType: 'none',
  auctionHours: 72,
  propertyType: 'residential',
  group: '',
  description: '',
})

export const creation = $state({
  draft: null,
  form: creationFormDefaults(),
})
