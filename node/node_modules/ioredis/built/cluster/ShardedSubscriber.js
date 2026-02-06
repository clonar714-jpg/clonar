"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const util_1 = require("./util");
const utils_1 = require("../utils");
const Redis_1 = require("../Redis");
const debug = (0, utils_1.Debug)("cluster:subscriberGroup:shardedSubscriber");
class ShardedSubscriber {
    constructor(emitter, options) {
        this.emitter = emitter;
        this.started = false;
        this.instance = null;
        // Store listener references for cleanup
        this.messageListeners = new Map();
        this.onEnd = () => {
            this.started = false;
            this.emitter.emit("-node", this.instance, this.nodeKey);
        };
        this.onError = (error) => {
            this.emitter.emit("nodeError", error, this.nodeKey);
        };
        this.onMoved = () => {
            this.emitter.emit("moved");
        };
        this.instance = new Redis_1.default({
            port: options.port,
            host: options.host,
            username: options.username,
            password: options.password,
            enableReadyCheck: false,
            offlineQueue: true,
            connectionName: (0, util_1.getConnectionName)("ssubscriber", options.connectionName),
            lazyConnect: true,
            tls: options.tls,
            /**
             * Disable auto reconnection for subscribers.
             * The ClusterSubscriberGroup will handle the reconnection.
             */
            retryStrategy: null,
        });
        this.nodeKey = (0, util_1.getNodeKey)(options);
        // Register listeners
        this.instance.once("end", this.onEnd);
        this.instance.on("error", this.onError);
        this.instance.on("moved", this.onMoved);
        for (const event of ["smessage", "smessageBuffer"]) {
            const listener = (...args) => {
                this.emitter.emit(event, ...args);
            };
            this.messageListeners.set(event, listener);
            this.instance.on(event, listener);
        }
    }
    async start() {
        if (this.started) {
            debug("already started %s", this.nodeKey);
            return;
        }
        try {
            await this.instance.connect();
            debug("started %s", this.nodeKey);
            this.started = true;
        }
        catch (err) {
            debug("failed to start %s: %s", this.nodeKey, err);
            this.started = false;
            throw err; // Re-throw so caller knows it failed
        }
    }
    stop() {
        this.started = false;
        if (this.instance) {
            this.instance.disconnect();
            this.instance.removeAllListeners();
            this.messageListeners.clear();
            this.instance = null;
        }
        debug("stopped %s", this.nodeKey);
    }
    isStarted() {
        return this.started;
    }
    getInstance() {
        return this.instance;
    }
    getNodeKey() {
        return this.nodeKey;
    }
}
exports.default = ShardedSubscriber;
