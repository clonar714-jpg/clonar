/// <reference types="node" />
import EventEmitter = require("events");
import { RedisOptions } from "./util";
import Redis from "../Redis";
export default class ShardedSubscriber {
    private readonly emitter;
    private readonly nodeKey;
    private started;
    private instance;
    private readonly messageListeners;
    constructor(emitter: EventEmitter, options: RedisOptions);
    private onEnd;
    private onError;
    private onMoved;
    start(): Promise<void>;
    stop(): void;
    isStarted(): boolean;
    getInstance(): Redis | null;
    getNodeKey(): string;
}
