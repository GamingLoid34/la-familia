const test = require("node:test");
const assert = require("node:assert");
const {
  classifyModes,
  normalizeDeparture,
  searchStops,
  _test,
} = require("../display_transit");

test("classifyModes: bitmask enligt officiell ResRobot v2.1-spec", () => {
  // 16 = Lokaltåg (Östgötapendeln, Pågatåg m.fl.)
  assert.deepStrictEqual(classifyModes({ products: 16 }), ["train"]);
  // 2 = Snabbtåg, 4 = Regionaltåg
  assert.deepStrictEqual(classifyModes({ products: 2 }), ["train"]);
  assert.deepStrictEqual(classifyModes({ products: 4 }), ["train"]);
  // 128 = Bussar, 8 = Expressbussar
  assert.deepStrictEqual(classifyModes({ products: 128 }), ["bus"]);
  assert.deepStrictEqual(classifyModes({ products: 8 }), ["bus"]);
});

test("classifyModes: kombinerad station och ren busshållplats", () => {
  // Tranås station: bitmask för både tåg (16 | 4 | 2 = 22) och buss (128 | 8 = 136) -> 158
  const tranasStationModes = classifyModes({ products: 158, name: "Tranås station" });
  assert.ok(tranasStationModes.includes("train"), "Tranås station ska innehålla 'train'");
  assert.ok(tranasStationModes.includes("bus"), "Tranås station ska innehålla 'bus'");

  // Ren busshållplats (t.ex. Tranås Storgatan 55): bitmask 128
  const busStopModes = classifyModes({ products: 128, name: "Tranås Storgatan 55" });
  assert.deepStrictEqual(busStopModes, ["bus"]);
  assert.strictEqual(busStopModes.includes("train"), false, "Ren busshållplats får INTE innehålla 'train'");
});

test("classifyModes: response cls och textmatchning", () => {
  // Cls från DepartureBoard
  assert.deepStrictEqual(classifyModes({ cls: 1 }), ["train"]);
  assert.deepStrictEqual(classifyModes({ cls: 2 }), ["train"]);
  assert.deepStrictEqual(classifyModes({ cls: 4 }), ["train"]);
  assert.deepStrictEqual(classifyModes({ cls: 16 }), ["train"]);
  assert.deepStrictEqual(classifyModes({ cls: 3 }), ["bus"]);
  assert.deepStrictEqual(classifyModes({ cls: 7 }), ["bus"]);

  // Textmatchning när cls saknas
  assert.deepStrictEqual(classifyModes({ name: "Tåg 8712" }), ["train"]);
  assert.deepStrictEqual(classifyModes({ catOutL: "Tåg" }), ["train"]);
  assert.deepStrictEqual(classifyModes({ name: "Buss 670" }), ["bus"]);
  assert.deepStrictEqual(classifyModes({ catOutL: "Buss" }), ["bus"]);
});

test("classifyModes: okänd produktklass ger ['unknown'] (aldrig tom eller gömd)", () => {
  // 512 = Taxi, 256 = Färja, 999 = framtida okänd kod
  const taxiModes = classifyModes({ products: 512 });
  assert.deepStrictEqual(taxiModes, ["unknown"]);

  const unknownClsModes = classifyModes({ cls: 99 });
  assert.deepStrictEqual(unknownClsModes, ["unknown"]);
});

test("normalizeDeparture: Östgötapendeln och buss normaliseras korrekt", () => {
  const trainDep = normalizeDeparture({
    name: "Östgötapendeln 8734",
    time: "14:25:00",
    direction: "Norrköping C (Tranås kn)",
    Product: [{
      cls: 16,
      operator: "Östgötatrafiken",
      catOutL: "Tåg",
      displayNumber: "8734",
    }],
  });
  assert.strictEqual(trainDep.line, "Östgötapendeln");
  assert.strictEqual(trainDep.mode, "train");
  assert.strictEqual(trainDep.destination, "Norrköping C");
  assert.strictEqual(trainDep.scheduled, "14:25");

  const busDep = normalizeDeparture({
    name: "Buss 670",
    time: "07:15:00",
    direction: "Eksjö",
    Product: [{
      cls: 7,
      operator: "JLT",
      catOutL: "Buss",
      displayNumber: "670",
    }],
  });
  assert.strictEqual(busDep.line, "670");
  assert.strictEqual(busDep.mode, "bus");
  assert.strictEqual(busDep.destination, "Eksjö");
});

test("searchStops: fixturtest Tranås station och ren busshållplats", async () => {
  _test.searchStopsCache.clear();

  // Mocka ResRobot location.name svar
  const originalFetch = global.fetch;
  const mockLocationResponse = {
    stopLocationOrCoordLocation: [
      {
        StopLocation: {
          id: "740000041",
          extId: "740000041",
          name: "Tranås station (Tranås kn)",
          products: 158, // Tåg + Buss
        },
      },
      {
        StopLocation: {
          id: "740040723",
          extId: "740040723",
          name: "Tranås Storgatan 55 (Tranås kn)",
          products: 128, // Endast buss
        },
      },
      {
        StopLocation: {
          id: "740099999",
          extId: "740099999",
          name: "Tranås Hamn",
          products: 256, // Färja -> unknown
        },
      },
    ],
  };

  global.fetch = async () => ({
    ok: true,
    json: async () => mockLocationResponse,
  });

  try {
    const result = await searchStops("Tranås", "dummy_key");
    assert.strictEqual(result.attribution, "data från Trafiklab.se");
    assert.strictEqual(result.stops.length, 3);

    // Tranås station
    const tranasStation = result.stops.find((s) => s.stopId === "740000041");
    assert.ok(tranasStation, "Tranås station ska finnas");
    assert.strictEqual(tranasStation.name, "Tranås station", "Kommun-suffix ska ha rensats");
    assert.ok(tranasStation.modes.includes("train"), "Tranås station ska innehålla 'train'");

    // Tranås Storgatan 55 (ren busshållplats)
    const tranasBuss = result.stops.find((s) => s.stopId === "740040723");
    assert.ok(tranasBuss, "Tranås Storgatan ska finnas");
    assert.strictEqual(tranasBuss.name, "Tranås Storgatan 55");
    assert.ok(tranasBuss.modes.includes("bus"), "Buss ska finnas");
    assert.strictEqual(tranasBuss.modes.includes("train"), false, "Får INTE innehålla 'train'");

    // Hamn (okänd/annan produktklass)
    const hamn = result.stops.find((s) => s.stopId === "740099999");
    assert.ok(hamn);
    assert.deepStrictEqual(hamn.modes, ["unknown"]);

    // Validera cache: andra anropet träffar cache
    global.fetch = async () => {
      throw new Error("Ska inte anropas vid cache-träff");
    };
    const cachedResult = await searchStops("tranås", "dummy_key");
    assert.strictEqual(cachedResult.stops.length, 3);

    // Validera söksträngens längd
    await assert.rejects(
      async () => await searchStops("a", "dummy_key"),
      /minst 2 tecken/
    );
  } finally {
    global.fetch = originalFetch;
    _test.searchStopsCache.clear();
  }
});
