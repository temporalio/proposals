# Schedules

- [Docs](https://docs.temporal.io/workflows/#schedules)
- gRPC API:
  - [methods](https://github.com/temporalio/api/blob/799926c86eb13d8a9717d3561ab9b0df43796c06/temporal/api/workflowservice/v1/service.proto#L328-L370)
  - [`request_response.proto`](https://github.com/temporalio/api/blob/799926c86eb13d8a9717d3561ab9b0df43796c06/temporal/api/workflowservice/v1/request_response.proto#L821-L957)
  - [`schedule/v1/message.proto`](https://github.com/temporalio/api/blob/master/temporal/api/schedule/v1/message.proto)
  - [`ScheduleOverlapPolicy` enum](https://github.com/temporalio/api/blob/master/temporal/api/enums/v1/schedule.proto)

## TS API

```ts
import { ScheduleClient, ScheduleOverlapPolicy } from '@temporalio/client'
import { addWeeks } from 'date-fns'
import { myWorkflow } from './workflows'

const client = new ScheduleClient();

const schedule = await client.create({
  id: 'schedule-biz-id',
  spec: {
    // every hour at minute 5
    intervals: [
      {
        every: '1h',
        at: '5m',
      },
    ],
    // every 20 days since epoch at day 2
    // intervals: [{
    //   every: '20d',
    //   at: '2d'
    // }]
    skip: [
      {
        // skip 11:05 pm
        hour: 23,
        minute: 5,
      },
    ],
    endAt: addWeeks(new Date(), 4),
    jitter: '30s',
    timezone: 'US/Pacific',
  },
  action: {
    workflowId: 'wf-biz-id',
    type: myWorkflow,
    args: ['arg1', 'arg2'],
  },
  overlap: ScheduleOverlapPolicy.BufferOne,
  catchupWindow: '2m',
  pauseOnFailure: true,
  note: 'started schedule',
  pause: true, // this sets `state.paused: true` (default false)
  limitedActions: 10,
  triggerImmediately: true,
  backfill: [
    {
      start: new Date(),
      end: new Date(),
      overlap: ScheduleOverlapPolicy.AllowAll,
    },
  ],
  memo,
  searchAttributes,
});

const schedule = client.getHandle('schedule-biz-id');

const scheduleDescription = await schedule.describe();

// For later, pending API finalization:
// https://github.com/temporalio/proposals/pull/62/files#r933532170
// const matchingStartTimes = await schedule.listMatchingTimes({ start: new Date(), end: new Date() })
// const matchingStartTimes = await client.listMatchingTimes({ spec, start, end })

await schedule.update(
  (schedule) => {
    schedule.spec.intervals[0].every = '1d';
    // unset with:
    // delete schedule.spec.intervals;

    // return false to stop retrying early
  },
  { retry: retryPolicy }
);

await schedule.trigger();
await schedule.backfill({ startAt: new Date(), endAt: addWeeks(new Date(), 1) }); // also takes array
await schedule.pause('note: pausing');
await schedule.unpause('now unpause');

await schedule.delete();

const { schedules, nextPageToken } = await client.listByPage({
  pageSize: 50,
  nextPageToken: 'base64',
});

for await (const schedule: Schedule of client.list()) {
  const { id, memo, searchAttributes } = schedule;
  // ...
}
```

### Types

```ts
import { DataConverter, LoadedDataConverter } from '@temporalio/common';
import { loadDataConverter } from '@temporalio/internal-non-workflow-common';
import {
  composeInterceptors,
  Headers,
  Replace,
  RetryPolicy,
  SearchAttributes,
  Workflow,
} from '@temporalio/internal-workflow-common';
import { temporal } from '@temporalio/proto';
import os from 'os';
import { Connection } from './connection';
import { ScheduleClientCallsInterceptor, ScheduleClientInterceptors } from './interceptors';
import { ConnectionLike, Metadata, WorkflowService } from './types';
import { WorkflowHandle, WorkflowStartOptions } from './workflow-client';

import type { NonNegativeInteger, RequireAtLeastOne } from 'type-fest';

// TODO is a non-generic NonNegativeInteger possible? The ones below error due to no type argument
export type PositiveInteger = Exclude<NonNegativeInteger, 0>;

/**
 * @format number of milliseconds or {@link https://www.npmjs.com/package/ms | ms-formatted string}
 */
export type Milliseconds = string | NonNegativeInteger;

/**
 * @format number of seconds or {@link https://www.npmjs.com/package/ms | ms-formatted string}
 */
export type Seconds = string | NonNegativeInteger;

export interface UpdateScheduleOptions {
  /**
   * @default TODO
   */
  retry?: RetryPolicy;
}

export interface Backfill {
  /** Time range to evaluate Schedule in. */
  startAt: Date;
  endAt: Date;

  /** Override Overlap Policy for this request. */
  overlapPolicyOverride?: ScheduleOverlapPolicy;
}

/**
 * Handle to a single Schedule
 */
export interface ScheduleHandle {
  /**
   * This Schedule's identifier
   */
  readonly id: string;

  /**
   * Update the Schedule
   */
  update(mutateFn: (schedule: ScheduleDescription) => void | false, options?: UpdateScheduleOptions): Promise<void>;

  /**
   * Delete the Schedule
   */
  delete(): Promise<void>;

  /**
   * Trigger an Action to be taken immediately
   */
  trigger(): Promise<void>;

  /**
   * Run though the specified time period(s) and take Actions as if that time passed by right now, all at once. The
   * Overlap Policy can be overridden for the scope of the Backfill.
   */
  backfill(options: Backfill | Backfill[]): Promise<void>;

  /**
   * Pause the Schedule
   */
  pause(note?: string): Promise<void>;

  /**
   * Unpause the Schedule
   */
  unpause(note?: string): Promise<void>;

  /**
   * Fetch the Schedule's description from the Server
   */
  describe(): Promise<ScheduleDescription>;

  /**
   * Get a handle to the most recent Action started
   */
  lastAction<T extends ScheduleActionType>(): Promise<HandleFor<T>>;

  /**
   * Readonly accessor to the underlying ScheduleClient
   */
  readonly client: ScheduleClient;
}

export type Base64 = string;

export interface Schedule {
  /**
   * Schedule Id
   *
   * We recommend using a meaningful business identifier.
   */
  id: string;

  /**
   * Additional non-indexed information attached to the Schedule. The values can be anything that is
   * serializable by the {@link DataConverter}.
   */
  memo?: Record<string, any>;

  /**
   * Additional indexed information attached to the Schedule. More info:
   * https://docs.temporal.io/docs/typescript/search-attributes
   *
   * Values are always converted using {@link JsonPayloadConverter}, even when a custom Data Converter is provided.
   */
  searchAttributes: SearchAttributes;

  // TODO flatten this?
  info: ScheduleInfo;
}

/**
 * The current Schedule details. They may not match the Schedule as created because:
 * - some fields in the state are modified automatically
 * - the schedule may have been modified by {@link ScheduleHandle.update} or
 *   {@link ScheduleHandle.pause}/{@link ScheduleHandle.unpause}
 */
export interface ScheduleDescription {
  /** When Actions should be taken */
  spec: RequireAtLeastOne<ScheduleSpec, 'calendars' | 'intervals'>;

  /**
   * Which Action to take
   */
  action: ScheduleActionOptions;

  /**
   * Controls what happens when an Action would be started by a Schedule at the same time that an older Action is still
   * running.
   *
   * @default {@link ScheduleOverlapPolicy.Skip}
   */
  overlap: ScheduleOverlapPolicy;

  /**
   * The Temporal Server might be down or unavailable at the time when a Schedule should take an Action. When the Server
   * comes back up, `catchupWindow` controls which missed Actions should be taken at that point. The default is one
   * minute, which means that the Schedule attempts to take any Actions that wouldn't be more than one minute late. It
   * takes those Actions according to the {@link ScheduleOverlapPolicy}. An outage that lasts longer than the Catchup
   * Window could lead to missed Actions. (But you can always {@link ScheduleHandle.backfill}.)
   *
   * @default 1 minute
   */
  catchupWindow: Milliseconds;

  /**
   * When an Action times out or reaches the end of its Retry Policy, {@link pause}.
   *
   * With {@link ScheduleOverlapPolicy.AllowAll}, this pause might not apply to the next Action, because the next Action
   * might have already started previous to the failed one finishing. Pausing applies only to Actions that are scheduled
   * to start after the failed one finishes.
   *
   * @default false
   */
  pauseOnFailure: boolean;

  /**
   * Informative human-readable message with contextual notes, e.g. the reason
   * a Schedule is paused. The system may overwrite this message on certain
   * conditions, e.g. when pause-on-failure happens.
   */
  note?: string;

  /**
   * Is currently paused.
   *
   * @default false
   */
  paused: boolean;

  /** Whether the number of Actions to take is limited. */
  actionsAreLimited: boolean;

  /**
   * Limit the number of Actions to take.
   *
   * This number is decremented after each Action is taken, and Actions are not
   * taken when the number is `0` (unless {@link ScheduleHandle.trigger} is called).
   *
   * @default unlimited
   */
  remainingActions?: NonNegativeInteger;
}

export interface ScheduleListPage {
  schedules: Schedule[];
  nextPageToken?: Base64;

  /**
   * Token to use to when calling {@link ScheduleClient.listByPage}.
   *
   * If `undefined`, there are no more Schedules.
   */
  nextPageToken?: Base64;
}

export type WorkflowExecution = Required<temporal.api.common.v1.IWorkflowExecution>;

export type ScheduleInfo = Schedule & {
  /** Number of Actions taken so far. */
  numActionsTaken: number;
  // TODO or numberOfActionsTaken etc?

  /** Number of times a scheduled Action was skipped due to missing the catchup window. */
  numActionsMissedCatchupWindow: number;

  /** Number of Actions skipped due to overlap. */
  numActionsSkippedOverlap: number;

  /**
   * Currently-running workflows started by this schedule. (There might be
   * more than one if the overlap policy allows overlaps.)
   * Note that the run_ids in here are the original execution run ids as
   * started by the schedule. If the workflows retried, did continue-as-new,
   * or were reset, they might still be running but with a different run_id.
   */
  runningWorkflows: WorkflowExecution[];

  /**
   * Most recent 10 Actions started (including manual triggers).
   *
   * Sorted from older start time to newer.
   */
  recentActions: ScheduleAction[];

  /** Next 10 scheduled Action times */
  nextActionTimes: Date[];

  createdAt: Date;
  lastUpdatedAt: Date;

  isValid(): boolean;

  /** Error for invalid schedule. If this is present, no actions will be taken. */
  invalidScheduleError?: string;
};

export interface ScheduleAction {
  /** Time that the Action was scheduled for, including jitter. */
  scheduledAt: Date;

  /** Time that the Action was actually taken. */
  takenAt: Date;

  /** If action was {@link StartWorkflowAction}. */
  workflow?: WorkflowExecution;
  // TODO or WorkflowHandle? would be more convenient, eg `const latestResult = await recentActions.pop().result()`
}

export interface ScheduleClientOptions {
  /**
   * {@link DataConverter} to use for serializing and deserializing payloads
   */
  dataConverter?: DataConverter;

  /**
   * Used to override and extend default Connection functionality
   *
   * Useful for injecting auth headers and tracing Workflow executions
   */
  interceptors?: ScheduleClientInterceptors;

  /**
   * Identity to report to the server
   *
   * @default `${process.pid}@${os.hostname()}`
   */
  identity?: string;

  /**
   * Connection to use to communicate with the server.
   *
   * By default `ScheduleClient` connects to localhost.
   *
   * Connections are expensive to construct and should be reused.
   */
  connection?: ConnectionLike;

  /**
   * Server namespace
   *
   * @default default
   */
  namespace?: string;
}

export type ScheduleClientOptionsWithDefaults = Replace<
  Required<ScheduleClientOptions>,
  {
    connection?: ConnectionLike;
  }
>;
export type LoadedScheduleClientOptions = ScheduleClientOptionsWithDefaults & {
  loadedDataConverter: LoadedDataConverter;
};

export function defaultScheduleClientOptions(): ScheduleClientOptionsWithDefaults {
  return {
    dataConverter: {},
    // The equivalent in Java is ManagementFactory.getRuntimeMXBean().getName()
    identity: `${process.pid}@${os.hostname()}`,
    interceptors: {},
    namespace: 'default',
  };
}

// TODO
// function ensureArgs<W extends Workflow, T extends ScheduleOptions<W>>(opts: T): Omit<T, 'args'> & { args: unknown[] } {
//   const { args, ...rest } = opts;
//   return { args: args ?? [], ...rest };
// }

interface SchdeduleHandleOptions extends GetSchdeduleHandleOptions {
  workflowId: string;
  runId?: string;
  interceptors: ScheduleClientCallsInterceptor[];
  /**
   * A runId to use for getting the workflow's result.
   *
   * - When creating a handle using `getHandle`, uses the provided runId or firstExecutionRunId
   * - When creating a handle using `start`, uses the returned runId (first in the chain)
   * - When creating a handle using `signalWithStart`, uses the the returned runId
   */
  runIdForResult?: string;
}

/**
 * Policy for overlapping Actions.
 */
export enum ScheduleOverlapPolicy {
  /**
   * Don't start a new Action.
   */
  Skip = 1,

  /**
   * Start another Action as soon as the current Action completes, but only buffer one Action in this way. If another
   * Action is supposed to start, but one Action is running and one is already buffered, then only the buffered one will
   * be started after the running Action finishes.
   */
  BufferOne,

  /**
   * Allows an unlimited number of Actions to buffer. They are started sequentially.
   */
  BufferAll,

  /**
   * Cancels the running Action, and then starts the new Action once the cancelled one completes.
   */
  CancelOther,

  /**
   * Terminate the running Action and start the new Action immediately.
   */
  TerminateOther,

  /**
   * Allow any number of Actions to start immediately.
   *
   * This is the only policy under which multiple Actions can run concurrently.
   */
  AllowAll,
}

checkExtends<temporal.api.enums.v1.schedule.ScheduleOverlapPolicy, ScheduleOverlapPolicy>();

export interface Backfill {
  start: Date;
  end: Date;
  /**
   * Override overlap policy for this request.
   */
  overlap?: ScheduleOverlapPolicy;
}

/**
 * The range of values depends on which, if any, fields are set:
 *
 * ```
 * {} -> all values
 * {start} -> start
 * {start, end} -> every value from start to end (implies step = 1)
 * {start, step} -> from start, by step (implies end is max for this field)
 * {start, end, step} -> from start to end, by step
 * {step} -> all values, by step (implies start and end are full range for this field)
 * {end} and {end, step} are not allowed
 * ```
 * TODO is there a way to express not allowed ^ in type?
 *
 * For example:
 *
 * ```
 * {start: 2, end: 10, step: 3} -> 2, 5, 8
 * ```
 */
export interface Range<Unit> {
  start?: Unit;
  end?: Unit;

  /**
   * The step to take between each value.
   *
   * @default 1
   */
  step?: PositiveInteger;
}

export type AnyValue = '*';

export type ZeroTo59 =
  | 0
  | 1
  | 2
  | 3
  | 4
  | 5
  | 6
  | 7
  | 8
  | 9
  | 10
  | 11
  | 12
  | 13
  | 14
  | 15
  | 16
  | 17
  | 18
  | 19
  | 20
  | 21
  | 22
  | 23
  | 24
  | 25
  | 26
  | 27
  | 28
  | 29
  | 30
  | 31
  | 32
  | 33
  | 34
  | 35
  | 36
  | 37
  | 38
  | 39
  | 40
  | 41
  | 42
  | 43
  | 44
  | 45
  | 46
  | 47
  | 48
  | 49
  | 50
  | 51
  | 52
  | 53
  | 54
  | 55
  | 56
  | 57
  | 58
  | 59;

export type Second = Range<ZeroTo59> | ZeroTo59;
export type Minute = Range<ZeroTo59> | ZeroTo59;

export type ZeroTo23 =
  | 0
  | 1
  | 2
  | 3
  | 4
  | 5
  | 6
  | 7
  | 8
  | 9
  | 10
  | 11
  | 12
  | 13
  | 14
  | 15
  | 16
  | 17
  | 18
  | 19
  | 20
  | 21
  | 22
  | 23;

export type Hour = Range<ZeroTo23> | ZeroTo23;

export type OneTo31 =
  | 1
  | 2
  | 3
  | 4
  | 5
  | 6
  | 7
  | 8
  | 9
  | 10
  | 11
  | 12
  | 13
  | 14
  | 15
  | 16
  | 17
  | 18
  | 19
  | 20
  | 21
  | 22
  | 23
  | 24
  | 25
  | 26
  | 27
  | 28
  | 29
  | 30
  | 31;

export type DayOfMonth = Range<OneTo31> | OneTo31;

export type OneTo12 = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12;

export type MonthName =
  | 'JAN'
  | 'JANUARY'
  | 'FEB'
  | 'FEBRUARY'
  | 'MAR'
  | 'MARCH'
  | 'APR'
  | 'APRIL'
  | 'MAY'
  | 'JUN'
  | 'JUNE'
  | 'JUL'
  | 'JULY'
  | 'AUG'
  | 'AUGUST'
  | 'SEP'
  | 'SEPTEMBER'
  | 'OCT'
  | 'OCTOBER'
  | 'NOV'
  | 'NOVEMBER'
  | 'DEC'
  | 'DECEMBER';

export type MonthValue = OneTo12 | MonthName;

export type Month = Range<MonthValue> | MonthValue;

export type TwoThousandTo2100 =
  | 2000
  | 2001
  | 2002
  | 2003
  | 2004
  | 2005
  | 2006
  | 2007
  | 2008
  | 2009
  | 2010
  | 2011
  | 2012
  | 2013
  | 2014
  | 2015
  | 2016
  | 2017
  | 2018
  | 2019
  | 2020
  | 2021
  | 2022
  | 2023
  | 2024
  | 2025
  | 2026
  | 2027
  | 2028
  | 2029
  | 2030
  | 2031
  | 2032
  | 2033
  | 2034
  | 2035
  | 2036
  | 2037
  | 2038
  | 2039
  | 2040
  | 2041
  | 2042
  | 2043
  | 2044
  | 2045
  | 2046
  | 2047
  | 2048
  | 2049
  | 2050
  | 2051
  | 2052
  | 2053
  | 2054
  | 2055
  | 2056
  | 2057
  | 2058
  | 2059
  | 2060
  | 2061
  | 2062
  | 2063
  | 2064
  | 2065
  | 2066
  | 2067
  | 2068
  | 2069
  | 2070
  | 2071
  | 2072
  | 2073
  | 2074
  | 2075
  | 2076
  | 2077
  | 2078
  | 2079
  | 2080
  | 2081
  | 2082
  | 2083
  | 2084
  | 2085
  | 2086
  | 2087
  | 2088
  | 2089
  | 2090
  | 2091
  | 2092
  | 2093
  | 2094
  | 2095
  | 2096
  | 2097
  | 2098
  | 2099
  | 2100;

/**
 * Temporal Server currently only supports specifying years in the range `[2000, 2100]`.
 */
export type Year = Range<TwoThousandTo2100> | TwoThousandTo2100;

/**
 * Both 0 and 7 mean Sunday
 */
export type ZeroTo7 = 0 | 1 | 2 | 3 | 4 | 5 | 7;

export type DayOfWeekName =
  | 'SU'
  | 'SUN'
  | 'SUNDAY'
  | 'MO'
  | 'MON'
  | 'MONDAY'
  | 'TU'
  | 'TUE'
  | 'TUES'
  | 'TUESDAY'
  | 'WE'
  | 'WED'
  | 'WEDNESDAY'
  | 'TH'
  | 'THU'
  | 'THUR'
  | 'THURS'
  | 'THURSDAY'
  | 'FR'
  | 'FRI'
  | 'FRIDAY'
  | 'SA'
  | 'SAT'
  | 'SATURDAY';

export type DayOfWeekValue = ZeroTo7 | DayOfWeekName;

// TODO can we do something to make it case insensitive?
// export type DayOfWeekValue<T> = ZeroTo7 | Uppercase<T> extends DayOfWeekName ? T : DayOfWeekName
export type DayOfWeek = Range<DayOfWeekValue> | DayOfWeekValue;

/**
 * An event specification relative to the calendar, similar to a traditional cron specification.
 *
 * A second in time matches if all fields match. This includes `dayOfMonth` and `dayOfWeek`.
 */
export interface CalendarSpec {
  /**
   * @default 0
   */
  second?: Second | Second[];

  /**
   * @default 0
   */
  minute?: Minute | Minute[];

  /**
   * @default 0
   */
  hour?: Hour | Hour[];

  /**
   * @default {@link AnyValue}
   */
  dayOfMonth?: DayOfMonth | DayOfMonth[];

  /**
   * @default {@link AnyValue}
   */
  month?: Month | Month[];

  /**
   * @default {@link AnyValue}
   */
  year?: Year | Year[];

  /**
   * Can accept 0 or 7 as Sunday.
   *
   * @default {@link AnyValue}
   */
  dayOfWeek?: DayOfWeek | DayOfWeek[];
}

/**
 * IntervalSpec matches times that can be expressed as:
 *
 * `Epoch + (n * every) + at`
 *
 * where `n` is any integer ≥ 0.
 *
 * For example, an `every` of 1 hour with `at` of zero would match every hour, on the hour. The same `every` but an `at`
 * of 19 minutes would match every `xx:19:00`. An `every` of 28 days with `at` zero would match `2022-02-17T00:00:00Z`
 * (among other times). The same `every` with `at` of 3 days, 5 hours, and 23 minutes would match `2022-02-20T05:23:00Z`
 * instead.
 */
export interface IntervalSpec {
  every: Seconds;

  /**
   * @default 0
   */
  at?: Seconds;
}

/**
 * A complete description of a set of absolute timestamps (possibly infinite) that an Action should occur at. These times
 * never change, except that the definition of a time zone can change over time (most commonly, when daylight saving
 * time policy changes for an area). To create a totally self-contained `ScheduleSpec`, use UTC.
 */
export interface ScheduleSpec {
  /** Calendar-based specifications of times. */
  calendars?: CalendarSpec[];

  /** Interval-based specifications of times. */
  intervals?: IntervalSpec[];

  /** Any timestamps matching any of the exclude_calendar specs will be skipped. */
  skip?: CalendarSpec[];

  /**
   * Any timestamps before `startAt` will be skipped. Together, `startAt` and `endAt` make an inclusive interval.
   *
   * @default The beginning of time
   */
  startAt?: Date;

  /**
   * Any timestamps after `endAt` will be skipped.
   *
   * @default The end of time
   */
  endAt?: Date;

  /**
   * All timestamps will be incremented by a random value from 0 to this amount of jitter.
   *
   * @default 1 second
   */
  jitter?: Milliseconds;

  /**
   * IANA timezone name, for example `US/Pacific`.
   * 
   * https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
   * 
   * @default UTC
   */
  timezone?: string;

  // Add to SDK if requested by users:
  //
  // bytes timezone_data = 11;
  //
  // Time zone to interpret all CalendarSpecs in.
  //
  // If unset, defaults to UTC. We recommend using UTC for your application if
  // at all possible, to avoid various surprising properties of time zones.
  //
  // Time zones may be provided by name, corresponding to names in the IANA
  // time zone database (see https://www.iana.org/time-zones). The definition
  // will be loaded by the Temporal server from the environment it runs in.
  //
  // If your application requires more control over the time zone definition
  // used, it may pass in a complete definition in the form of a TZif file
  // from the time zone database. If present, this will be used instead of
  // loading anything from the environment. You are then responsible for
  // updating timezone_data when the definition changes.
  //
  // Calendar spec matching is based on literal matching of the clock time
  // with no special handling of DST: if you write a calendar spec that fires
  // at 2:30am and specify a time zone that follows DST, that action will not
  // be triggered on the day that has no 2:30am. Similarly, an action that
  // fires at 1:30am will be triggered twice on the day that has two 1:30s.
}

export type StartWorkflowAction<Action extends Workflow> = Omit<
  WorkflowStartOptions<Action>,
  'workflowIdReusePolicy' | 'cronSchedule' | 'followRuns'
> & {
  /**
   * Metadata that's propagated between workflows and activities? TODO someone explain headers to me so I can improve
   * this apidoc and maybe:
   * - remove from here and only expose to interceptor?
   * - or make it Record<string, unknown> and apply client's data converter?
   */
  headers: Headers;
};

export type ScheduleActionType = Workflow;

/**
 * Currently, Temporal Server only supports {@link StartWorkflowAction}.
 */
export type ScheduleActionOptions<Action extends ScheduleActionType = ScheduleActionType> = StartWorkflowAction<Action>;
// in future:
// type SomethingElse = 'hi'
// type ScheduleAction = Workflow | SomethingElse
// type ExpectsSomethingElse<Action extends SomethingElse> = Action extends SomethingElse ? Action : number;
// type StartSomethingElseAction<Action extends SomethingElse> = ExpectsSomethingElse<Action>
// type ScheduleActionOptions<Action extends ScheduleAction> = Action extends Workflow
//   ? StartWorkflowAction<Action>
//   : Action extends SomethingElse
//     ? StartSomethingElseAction<Action>
//     : never;

export type HandleFor<T> = T extends Workflow ? WorkflowHandle<T> : never;

/**
 * Options for starting a Workflow
 */
export interface ScheduleOptions<Action extends ScheduleActionType> {
  /**
   * Schedule Id
   *
   * We recommend using a meaningful business identifier.
   */
  id: string;

  /** When Actions should be taken */
  spec: RequireAtLeastOne<ScheduleSpec, 'calendars' | 'intervals'>;

  /**
   * Which Action to take
   */
  action: ScheduleActionOptions<Action>;

  /**
   * Controls what happens when an Action would be started by a Schedule at the same time that an older Action is still
   * running.
   *
   * @default {@link ScheduleOverlapPolicy.Skip}
   */
  overlap?: ScheduleOverlapPolicy;

  /**
   * The Temporal Server might be down or unavailable at the time when a Schedule should take an Action. When the Server
   * comes back up, `catchupWindow` controls which missed Actions should be taken at that point. The default is one
   * minute, which means that the Schedule attempts to take any Actions that wouldn't be more than one minute late. It
   * takes those Actions according to the {@link ScheduleOverlapPolicy}. An outage that lasts longer than the Catchup
   * Window could lead to missed Actions. (But you can always {@link ScheduleHandle.backfill}.)
   *
   * @default 1 minute
   */
  catchupWindow?: Milliseconds;

  /**
   * When an Action times out or reaches the end of its Retry Policy, {@link pause}.
   *
   * With {@link ScheduleOverlapPolicy.AllowAll}, this pause might not apply to the next Action, because the next Action
   * might have already started previous to the failed one finishing. Pausing applies only to Actions that are scheduled
   * to start after the failed one finishes.
   *
   * @default false
   */
  pauseOnFailure?: boolean;

  /**
   * Informative human-readable message with contextual notes, e.g. the reason
   * a Schedule is paused. The system may overwrite this message on certain
   * conditions, e.g. when pause-on-failure happens.
   */
  note?: string;

  /**
   * Start in paused state.
   *
   * @default false
   */
  pause?: boolean;

  /**
   * Limit the number of Actions to take.
   *
   * This number is decremented after each Action is taken, and Actions are not
   * taken when the number is `0` (unless {@link ScheduleHandle.trigger} is called).
   *
   * @default unlimited
   */
  remainingActions?: NonNegativeInteger;

  /**
   * Trigger one Action immediately.
   *
   * @default false
   */
  triggerImmediately?: boolean;

  /**
   * Runs though the specified time periods and takes Actions as if that time passed by right now, all at once. The
   * overlap policy can be overridden for the scope of the backfill.
   */
  backfill?: Backfill[];

  /**
   * Additional non-indexed information attached to the Schedule. The values can be anything that is
   * serializable by the {@link DataConverter}.
   */
  memo?: Record<string, any>;

  /**
   * Additional indexed information attached to the Schedule. More info:
   * https://docs.temporal.io/docs/typescript/search-attributes
   *
   * Values are always converted using {@link JsonPayloadConverter}, even when a custom Data Converter is provided.
   */
  searchAttributes?: SearchAttributes;
}

export interface ListScheduleOptions {
  /**
   * How many results to return
   * @default 1000
   */
  pageSize?: number;

  /** Token to get the next page of results */
  nextPageToken?: Base64;
}

/**
 * Client for starting Workflow executions and creating Workflow handles
 */
export class ScheduleClient {
  public readonly options: LoadedScheduleClientOptions;
  public readonly connection: ConnectionLike;

  constructor(options?: ScheduleClientOptions) {
    this.connection = options?.connection ?? Connection.lazy();
    this.options = {
      ...defaultScheduleClientOptions(),
      ...options,
      loadedDataConverter: loadDataConverter(options?.dataConverter),
    };
  }

  /**
   * Raw gRPC access to the Temporal service. Schedule-related methods are included in {@link WorkflowService}.
   *
   * **NOTE**: The namespace provided in {@link options} is **not** automatically set on requests made to the service.
   */
  get scheduleService(): WorkflowService {
    return this.connection.workflowService;
  }

  /**
   * Set the deadline for any service requests executed in `fn`'s scope.
   */
  async withDeadline<R>(deadline: number | Date, fn: () => Promise<R>): Promise<R> {
    return await this.connection.withDeadline(deadline, fn);
  }

  /**
   * Set metadata for any service requests executed in `fn`'s scope.
   *
   * @returns returned value of `fn`
   *
   * @see {@link Connection.withMetadata}
   */
  async withMetadata<R>(metadata: Metadata, fn: () => Promise<R>): Promise<R> {
    return await this.connection.withMetadata(metadata, fn);
  }

  /**
   * Create a new Schedule.
   */
  public async create<Action extends ScheduleActionType>(options: ScheduleOptions<Action>): Promise<ScheduleHandle> {  }

  /**
   * List Schedules with an `AsyncIterator`:
   *
   * ```ts
   * for await (const schedule: Schedule of client.list()) {
   *   const { id, memo, searchAttributes } = schedule
   *   // ...
   * }
   * ```
   */
  public list(options?: ListScheduleOptions): AsyncIterator<Schedule> {}

  /** List Schedules, one page at a time */
  public async listByPage(options?: ListScheduleOptions): Promise<ScheduleListPage> {}

  /**
   * Get a handle to a Schedule
   *
   * This method does not validate `scheduleId`. If there is no Schedule with the given `scheduleId`, handle
   * methods like `handle.describe()` will throw a {@link ScheduleNotFoundError} error.
   */
  public getHandle(scheduleId: string): ScheduleHandle {  }
}
```

### Higher-level client

```ts
import { Client } from '@temporalio/client'

const client = new Client(options)

client.schedule.create()
client.workflow.start() 
client.asyncCompletion.heartbeat()
client.operator.addSearchAttributes()

interface ClientOptions {
  dataConverter?: DataConverter;
  interceptors?: {
    workflow: WorkflowClientInterceptors,
    schedule: ScheduleClientInterceptors,
  };
  identity?: string;
  connection?: ConnectionLike;
  namespace?: string;
  queryRejectCondition?: temporal.api.enums.v1.QueryRejectCondition;
}
```

### Interceptors

```ts
interface ScheduleClientCallsInterceptor {
  /**
   * Intercept a service call to CreateSchedule
   */
  create?: (input: ScheduleStartInput, next: Next<this, 'create'>) => Promise<string /* conflictToken */>;
  describe
  listMatchingTimes
  update
  patch
  delete
  list
}

interface ScheduleClientCallsInterceptorFactoryInput {
  id: string;
}

/**
 * A function that takes a {@link ScheduleClientCallsInterceptorFactoryInput} and returns an interceptor
 */
export interface ScheduleClientCallsInterceptorFactory {
  (input: ScheduleClientCallsInterceptorFactoryInput): ScheduleClientCallsInterceptor;
}

/**
 * A mapping of interceptor type of a list of factory functions
 */
export interface ScheduleClientInterceptors {
  calls?: ScheduleClientCallsInterceptorFactory[];
}
```