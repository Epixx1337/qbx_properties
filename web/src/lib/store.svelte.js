export const app = $state({
  view: null,
  tab: 'market',
  isRealtor: false,
})

export const furniture = $state({
  categories: {},
  category: null,
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
  exitConfirm: false,
  restorePrompt: null,
})

export const market = $state({
  listings: [],
  sizes: {},
  sizeOrder: [],
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
  apartment: false,
  nearby: [],
  utilities: null,
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
})

export const creation = $state({
  draft: null,
  form: creationFormDefaults(),
})
