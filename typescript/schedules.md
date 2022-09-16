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
import { addWeeks, subDays } from 'date-fns'
import { myWorkflow } from './workflows'

const client = new ScheduleClient();

const schedule = await client.create({
  id: 'schedule-biz-id',
  spec: {
    // Schedule fires at combination of all `intervals` and `calendars`, minus the `skip` calendar:
    intervals: [
      // every hour at minute 5
      {
        every: '1h',
        offset: '5m',
      },
      // every 20 days since epoch at day 2
      {
        every: '20d',
        offset: '2d',
      },
    ],
    calendars: [{
      // at noon on the 1st, 3rd, 5th, 7th, 9th, and 22nd days of the month
      hour: 12,
      dayOf: [{
        start: 1,
        end: 10,
        step: 2,
      }, 22],
    }],
    skip: [
      {
        // skip 11:05 pm daily
        hour: 23,
        minute: 5,
      },
    ],
    startAt: new Date(),
    endAt: addWeeks(new Date(), 4),
    jitter: '30s',
    timezone: 'US/Pacific',
  },
  action: {
    type: 'startWorkflow',
    workflowId: 'wf-biz-id',
    workflowType: myWorkflow,
    args: ['arg1', 'arg2'],
  },
  overlap: ScheduleOverlapPolicy.BUFFER_ONE,
  catchupWindow: '2m',
  pauseOnFailure: true,
  note: 'started demo schedule',
  paused: true, // start paused
  limitedActions: 10,
  triggerImmediately: true,
  backfill: [
    {
      start: subDays(new Date(), 5),
      end: new Date(),
      overlap: ScheduleOverlapPolicy.ALLOW_ALL,
    },
  ],
  memo: { startedBy: 'Loren' },
  searchAttributes: { SearchField: 'foo' },
});

const scheduleDescription = await schedule.describe();

const sameSchedule = client.getHandle('schedule-biz-id');

const newSimilarSchedule = await client.create(scheduleDescription.copyOptions({
  id: 'new-id',
  action: {
    workflowId: 'wf-biz-id-2',
    type: differentWorkflow,
  }
})

// For later, pending API finalization:
// https://github.com/temporalio/proposals/pull/62/files#r933532170
// const matchingStartTimes = await schedule.listMatchingTimes({ start: new Date(), end: new Date() })
// and/or:
// const matchingStartTimes = await client.listMatchingTimes({ spec, start, end })

await schedule.update(
  (schedule) => {
    schedule.spec.intervals[0].every = '1d';
    return schedule
    // to not update or stop retrying early:
    // return
  },
  { maximumAttempts: 10 }
);

await schedule.trigger();
await schedule.backfill({ startAt: new Date(), endAt: addWeeks(new Date(), 1) }); // also takes array
await schedule.pause('note: pausing');
await schedule.unpause('now unpause');

await schedule.delete();

for await (const schedule: Schedule of client.list()) {
  const { id, memo, searchAttributes } = schedule;
  // ...
}
```

### Types

````ts
import { DataConverter, LoadedDataConverter } from '@temporalio/common';
import { loadDataConverter } from '@temporalio/internal-non-workflow-common';
import {
  composeInterceptors,
  Headers,
  Replace,
  RetryPolicy,
  SearchAttributes,
  Workflow, // type Workflow = (...args: any[]) => WorkflowReturnType;
} from '@temporalio/internal-workflow-common';
import { temporal } from '@temporalio/proto';
import os from 'os';
import { Connection } from './connection';
import { ScheduleClientCallsInterceptor, ScheduleClientInterceptors } from './interceptors';
import { ConnectionLike, Metadata, WorkflowService } from './types';
import { WorkflowHandle, WorkflowStartOptions } from './workflow-client';

export interface UpdateScheduleOptions {
  /**
   * How many times to retry the update.
   *
   * Set to `1` if you don't want to retry.
   *
   * @default 3
   */
  maximumAttempts?: number;
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
   *
   * This function calls `.describe()` and then tries to send the update to the Server. If the Schedule has changed
   * between the time of `.describe()` and the update, the Server throws an error, and the SDK retries, up to
   * {@link UpdateScheduleOptions.maximumAttempts}.
   *
   * If, inside `updateFn`, you no longer want the SDK to try sending the update to the Server, return undefined.
   */
  update(updateFn: (schedule: Schedule) => Schedule | undefined, options?: UpdateScheduleOptions): Promise<void>;

  /**
   * Delete the Schedule
   */
  delete(): Promise<void>;

  /**
   * Trigger an Action to be taken immediately
   *
   * @param overlap Override the Overlap Policy for this one trigger. Defaults to {@link ScheduleOverlapPolicy.ALLOW_ALL}.
   */
  trigger(overlap?: ScheduleOverlapPolicy;): Promise<void>;

  /**
   * Run though the specified time period(s) and take Actions as if that time passed by right now, all at once. The
   * Overlap Policy can be overridden for the scope of the Backfill.
   */
  backfill(options: Backfill | Backfill[]): Promise<void>;

  /**
   * Pause the Schedule
   *
   * @param note A new {@link Schedule.note}. Defaults to `"Paused via TypeScript SDK"`
   * @throws {@link ValueError} if empty string is passed
   */
  pause(note?: string): Promise<void>;

  /**
   * Unpause the Schedule
   *
   * @param note A new {@link Schedule.note}. Defaults to `"Unpaused via TypeScript SDK"`
   * @throws {@link ValueError} if empty string is passed
   */
  unpause(note?: string): Promise<void>;

  /**
   * Fetch the Schedule's description from the Server
   */
  describe(): Promise<Schedule>;

  // we won't have this helper in TS because it involves an implicit client, but other SDKs may want this
  lastAction<T extends ScheduleActionType>(): Promise<HandleFor<T>>;

  /**
   * Readonly accessor to the underlying ScheduleClient
   */
  readonly client: ScheduleClient;
}

export interface ListScheduleEntry {
  /**
   * Schedule Id
   *
   * We recommend using a meaningful business identifier.
   */
  id: string;

  /** When Actions are taken */
  spec: RequireAtLeastOne<ScheduleSpecDescription, 'calendars' | 'intervals'>;

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

  /**
   * Informative human-readable message with contextual notes, e.g. the reason
   * a Schedule is paused. The system may overwrite this message on certain
   * conditions, e.g. when pause-on-failure happens.
   */
  note?: string;

  /**
   * Whether Schedule is currently paused.
   *
   * @default false
   */
  paused: boolean;

  /**
   * Present if action is a {@link StartWorkflowAction}.
   */
  workflowType?: string;

  /**
   * Most recent 10 Actions started (including manual triggers).
   *
   * Sorted from older start time to newer.
   */
  recentActions: ScheduleAction[];

  /** Next 10 scheduled Action times */
  nextActionTimes: Date[];
}

/**
 * The current Schedule details. They may not match the Schedule as created because:
 * - some fields in the state are modified automatically
 * - the schedule may have been modified by {@link ScheduleHandle.update} or
 *   {@link ScheduleHandle.pause}/{@link ScheduleHandle.unpause}
 */
export type Schedule = ListScheduleEntry & {
  /**
   * Which Action to take
   */
  action: ScheduleActionOptions;

  /**
   * Controls what happens when an Action would be started by a Schedule at the same time that an older Action is still
   * running.
   *
   * @default {@link ScheduleOverlapPolicy.SKIP}
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
   * @format number of milliseconds
   */
  catchupWindow: number;

  /**
   * When an Action times out or reaches the end of its Retry Policy, {@link pause}.
   *
   * With {@link ScheduleOverlapPolicy.ALLOW_ALL}, this pause might not apply to the next Action, because the next Action
   * might have already started previous to the failed one finishing. Pausing applies only to Actions that are scheduled
   * to start after the failed one finishes.
   *
   * @default false
   */
  pauseOnFailure: boolean;

  /**
   * The Actions remaining in this Schedule. Once this number hits `0`, no further Actions are taken (unless {@link
   * ScheduleHandle.trigger} is called).
   *
   * @default undefined (unlimited)
   */
  remainingActions?: number;


  /** Number of Actions taken so far. */
  numActionsTaken: number;

  /** Number of times a scheduled Action was skipped due to missing the catchup window. */
  numActionsMissedCatchupWindow: number;

  /** Number of Actions skipped due to overlap. */
  numActionsSkippedOverlap: number;

  /**
   * Currently-running workflows started by this schedule. (There might be
   * more than one if the overlap policy allows overlaps.)
   */
  runningWorkflows: WorkflowExecutionWithFirstExecutionRunId[];

  createdAt: Date;
  lastUpdatedAt: Date;

  /**
   * Create a {@link ScheduleOptions} object based on this `Schedule` to use with {@link ScheduleClient.create}.
   */
  copyOptions<Action extends ScheduleActionType>(overrides: ScheduleOptionsOverrides<Action>): ScheduleOptions;
}

/**
 * Make all properties optional.
 *
 * If original Schedule is deleted, okay to use same `id`.
 */
export type ScheduleOptionsOverrides<Action> = Partial<ScheduleOptions<Action>>


export interface WorkflowExecutionWithFirstExecutionRunId {
  workflowId: string;

  /**
   * The Run Id of the original execution that was started by the Schedule. If the Workflow retried, did
   * Continue-As-New, or was Reset, the following runs would have different Run Ids.
   */
  firstExecutionRunId: string;
}

export interface ScheduleAction {
  /** Time that the Action was scheduled for, including jitter. */
  scheduledAt: Date;

  /** Time that the Action was actually taken. */
  takenAt: Date;

  /** If action was {@link StartWorkflowAction}. */
  workflow?: WorkflowExecutionWithFirstExecutionRunId;
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

/**
 * Policy for overlapping Actions.
 */
export enum ScheduleOverlapPolicy {
  /**
   * Use server default (currently SKIP).
   *
   * TODO remove this field if this issue is implemented: https://github.com/temporalio/temporal/issues/3240
   */
  UNSPECIFIED = 0,

  /**
   * Don't start a new Action.
   */
  SKIP,

  /**
   * Start another Action as soon as the current Action completes, but only buffer one Action in this way. If another
   * Action is supposed to start, but one Action is running and one is already buffered, then only the buffered one will
   * be started after the running Action finishes.
   */
  BUFFER_ONE,

  /**
   * Allows an unlimited number of Actions to buffer. They are started sequentially.
   */
  BUFFER_ALL,

  /**
   * Cancels the running Action, and then starts the new Action once the cancelled one completes.
   */
  CANCEL_OTHER,

  /**
   * Terminate the running Action and start the new Action immediately.
   */
  TERMINATE_OTHER,

  /**
   * Allow any number of Actions to start immediately.
   *
   * This is the only policy under which multiple Actions can run concurrently.
   */
  ALLOW_ALL,
}

checkExtendsWithoutPrefix<
  temporal.api.enums.v1.schedule.ScheduleOverlapPolicy,
  ScheduleOverlapPolicy,
  'SCHEDULE_OVERLAP_POLICY_'
>();

export interface Backfill {
  /** Time range to evaluate Schedule in. */
  start: Date;
  end: Date;

  /**
   * Override the Overlap Policy for this request.
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
 * TODO is there a way to express not allowed ^ in type?
 * ```
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

export type NumberRange = Range<number> | number
export type NumberSpec = NumberRange | NumberRange[] | string;
export type NumberSpecDescription = Range<number>[];

export type Month = 'JANUARY' | 'FEBRUARY' | 'MARCH' | 'APRIL' | 'MAY' | 'JUNE' | 'JULY' | 'AUGUST' | 'SEPTEMBER' | 'OCTOBER' | 'NOVEMBER' | 'DECEMBER';
export type MonthRange = Range<Month> | Month;
export type MonthSpec = MonthRange | MonthRange[] | string;
export type MonthSpecDescription = Range<Month>[];

export type Day = 'SUNDAY' | 'MONDAY' | 'TUESDAY' | 'WEDNESDAY' | 'THURSDAY' | 'FRIDAY' | 'SATURDAY';
export type DayRange = Range<Day> | Day;
export type DaySpec = DayRange | DayRange[] | string;
export type DaySpecDescription = Range<Day>[];

/**
 * An event specification relative to the calendar, similar to a traditional cron specification.
 *
 * A second in time matches if all fields match. This includes `dayOfMonth` and `dayOfWeek`.
 */
export interface CalendarSpec {
  /**
   * Valid values: 0–59
   *
   * @default 0
   */
  second?: NumberSpec;

  /**
   * Valid values: 0–59
   *
   * @default 0
   */
  minute?: NumberSpec;

  /**
   * Valid values: 0–59
   *
   * @default 0
   */
  hour?: NumberSpec;

  /**
   * Valid values: 1–31
   *
   * @default '*'
   */
  dayOfMonth?: NumberSpec;

  /**
   * @default '*'
   */
  month?: MonthSpec;

  /**
   * Use full years, like `2030`
   *
   * @default '*'
   */
  year?: NumberSpec;

  /**
   * @default '*'
   */
  dayOfWeek?: DaySpec;
}

/**
 * The version of {@link CalendarSpec} that you get back from {@link ScheduleHandle.describe}
 */
export interface CalendarSpecDescription {
  /**
   * Valid values: 0–59
   *
   * @default `[{ start: 0 }]`
   */
  second?: NumberSpecDescription;

  /**
   * Valid values: 0–59
   *
   * @default `[{ start: 0 }]`
   */
  minute?: NumberSpecDescription;

  /**
   * Valid values: 0–59
   *
   * @default `[{ start: 0 }]`
   */
  hour?: NumberSpecDescription;

  /**
   * Valid values: 1–31
   *
   * @default `[{ start: 1, end: 31 }]`
   */
  dayOfMonth?: NumberSpecDescription;

  /**
   * @default `[{ start: 'JANUARY' , end: 'DECEMBER' }]`
   */
  month?: MonthSpecDescription;

  /**
   * Use full years, like `2030`
   *
   * @default `[{ start: 2000, step: 1 }]`
   */
  year?: NumberSpecDescription;

  /**
   * @default `[{ start: 'SUNDAY', end: 'SATURDAY' }]`
   */
  dayOfWeek?: DaySpecDescription;
}

/**
 * IntervalSpec matches times that can be expressed as:
 *
 * `Epoch + (n * every) + offset`
 *
 * where `n` is all integers ≥ 0.
 *
 * For example, an `every` of 1 hour with `offset` of zero would match every hour, on the hour. The same `every` but an `offset`
 * of 19 minutes would match every `xx:19:00`. An `every` of 28 days with `offset` zero would match `2022-02-17T00:00:00Z`
 * (among other times). The same `every` with `offset` of 3 days, 5 hours, and 23 minutes would match `2022-02-20T05:23:00Z`
 * instead.
 */
export interface IntervalSpec {
  /**
   * Value is rounded to the nearest second.
   *
   * @format number of milliseconds or {@link https://www.npmjs.com/package/ms | ms-formatted string}
   */
  every: number | string;

  /**
   * Value is rounded to the nearest second.
   *
   * @default 0
   * @format number of milliseconds or {@link https://www.npmjs.com/package/ms | ms-formatted string}
   */
  offset?: number | string;
}

/**
 * The version of {@link IntervalSpec} that you get back from {@link ScheduleHandle.describe}
 */
export interface IntervalSpecDescription {
  /**
   * Value is rounded to the nearest second.
   *
   * @format number of milliseconds
   */
  every: number;

  /**
   * Value is rounded to the nearest second.
   *
   * @default 0
   * @format number of milliseconds
   */
  offset?: number;
}

/**
 * A complete description of a set of absolute times (possibly infinite) that an Action should occur at.
 * The times are the union of `calendars`, `intervals`, and `cronExpressions`, minus the `skip` times. These times
 * never change, except that the definition of a time zone can change over time (most commonly, when daylight saving
 * time policy changes for an area). To create a totally self-contained `ScheduleSpec`, use UTC.
 */
export interface ScheduleSpec {
  /** Calendar-based specifications of times. */
  calendars?: CalendarSpec[];

  /** Interval-based specifications of times. */
  intervals?: IntervalSpec[];

  /**
   * [Cron expressions](https://crontab.guru/)
   *
   * For example, `0 12 * * MON-WED,FRI` is every M/Tu/W/F at noon, and is equivalent to this {@link CalendarSpec}:
   *
   * ```ts
   * {
   *   hour: 12,
   *   dayOfWeek: [{
   *     start: 'MONDAY'
   *     end: 'WEDNESDAY'
   *   }, 'FRIDAY']
   * }
   * ```
   *
   * The string can have 5, 6, or 7 fields, separated by spaces, and they are interpreted in the
   * same way as a {@link CalendarSpec}.
   *
   * - 5 fields:         minute, hour, day_of_month, month, day_of_week
   * - 6 fields:         minute, hour, day_of_month, month, day_of_week, year
   * - 7 fields: second, minute, hour, day_of_month, month, day_of_week, year
   *
   * Notes:
   *
   * - If year is not given, it defaults to *.
   * - If second is not given, it defaults to 0.
   * - Shorthands @yearly, @monthly, @weekly, @daily, and @hourly are also
   * accepted instead of the 5-7 time fields.
   * - @every <interval>[/<phase>] is accepted and gets compiled into an
   * IntervalSpec instead. <interval> and <phase> should be a decimal integer
   * with a unit suffix s, m, h, or d.
   * - Optionally, the string can be preceded by CRON_TZ=<timezone name> or
   * TZ=<timezone name>, which will get copied to {@link timezone}. (In which case the {@link timezone} field should be left empty.)
   * - Optionally, "#" followed by a comment can appear at the end of the string.
   * - Note that the special case that some cron implementations have for
   * treating day_of_month and day_of_week as "or" instead of "and" when both
   * are set is not implemented.
   */
  cronExpressions?: string[];

  /**
   * Any matching times will be skipped.
   *
   * All aspects of the CalendarSpec—including seconds—must match a time for the time to be skipped.
   */
  skip?: CalendarSpec[];
  // TODO see if users want to be able to skip an IntervalSpec
  // https://github.com/temporalio/api/pull/230/files#r956434347

  /**
   * Any times before `startAt` will be skipped. Together, `startAt` and `endAt` make an inclusive interval.
   *
   * @default The beginning of time
   */
  startAt?: Date;

  /**
   * Any times after `endAt` will be skipped.
   *
   * @default The end of time
   */
  endAt?: Date;

  /**
   * All times will be incremented by a random value from 0 to this amount of jitter.
   *
   * @default 0
   * @format number of milliseconds or {@link https://www.npmjs.com/package/ms | ms-formatted string}
   */
  jitter?: number | string;

  /**
   * IANA timezone name, for example `US/Pacific`.
   *
   * https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
   *
   * The definition will be loaded by Temporal Server from the environment it runs in.
   *
   * Calendar spec matching is based on literal matching of the clock time
   * with no special handling of DST: if you write a calendar spec that fires
   * at 2:30am and specify a time zone that follows DST, that action will not
   * be triggered on the day that has no 2:30am. Similarly, an action that
   * fires at 1:30am will be triggered twice on the day that has two 1:30s.
   *
   * Also note that no actions are taken on leap-seconds (e.g. 23:59:60 UTC).
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
  // Time zones may be provided by name, corresponding to names in the IANA
  // time zone database (see https://www.iana.org/time-zones). The definition
  // will be loaded by the Temporal server from the environment it runs in.
  //
  // If your application requires more control over the time zone definition
  // used, it may pass in a complete definition in the form of a TZif file
  // from the time zone database. If present, this will be used instead of
  // loading anything from the environment. You are then responsible for
  // updating timezone_data when the definition changes.
}

/**
 * The version of {@link ScheduleSpec} that you get back from {@link ScheduleHandle.describe}
 */
export type ScheduleSpecDescription = Omit<ScheduleSpec, 'calendars' | 'intervals' | 'cronExpressions' | 'skip' | 'jitter' > & {
  /** Calendar-based specifications of times. */
  calendars?: CalendarSpecDescription[];

  /** Interval-based specifications of times. */
  intervals?: IntervalSpecDescription[];

  /** Any matching times will be skipped. */
  skip?: CalendarSpecDescription[];

  /**
   * All times will be incremented by a random value from 0 to this amount of jitter.
   *
   * @default 1 second
   * @format number of milliseconds
   */
  jitter?: number;
}

export type StartWorkflowAction<Action extends Workflow> = Omit<
  WorkflowStartOptions<Action>,
  'workflowIdReusePolicy' | 'cronSchedule' | 'followRuns'
> & {
  // This is most convenient for TS typing. Other SDKs may want to implement this differently, for example nesting:
  // action: {
  //   startWorkflow: {
  //     workflowId: 'wf-biz-id',
  //     ...
  //   }
  // }
  type: 'startWorkflow',

  workflowType: string | Action;

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
// type SomethingElse = { fieldFoo: string, type: 'startFoo' }
// type ScheduleActionType = Workflow | SomethingElse
// type ExpectsSomethingElse<Action extends SomethingElse> = Action extends SomethingElse ? Action : number;
// type StartSomethingElseAction<Action extends SomethingElse> = ExpectsSomethingElse<Action>
// type ScheduleActionOptions<Action extends ScheduleActionType> =
//   StartWorkflowAction<Action> | StartSomethingElseAction<Action>

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
   * running. This can be changed after a Schedule has taken some Actions, and some changes might produce
   * unintuitive results. In general, the later policy overrides the earlier policy.
   *
   * @default {@link ScheduleOverlapPolicy.SKIP}
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
   * @format number of milliseconds or {@link https://www.npmjs.com/package/ms | ms-formatted string}
   */
  catchupWindow?: number | string;

  /**
   * When an Action times out or reaches the end of its Retry Policy, {@link pause}.
   *
   * With {@link ScheduleOverlapPolicy.ALLOW_ALL}, this pause might not apply to the next Action, because the next Action
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
  paused?: boolean;

  /**
   * Limit the number of Actions to take.
   *
   * This number is decremented after each Action is taken, and Actions are not
   * taken when the number is `0` (unless {@link ScheduleHandle.trigger} is called).
   *
   * @default unlimited
   */
  remainingActions?: number;

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
   * How many results to fetch from the Server at a time.
   * @default 1000
   */
  pageSize?: number;
}

/**
 * Thrown from {@link ScheduleClient.create} if there's a running (not deleted) Schedule with the given `id`.
 */
export class ScheduleAlreadyRunning extends Error {
  public readonly name: string = 'ScheduleAlreadyRunning';

  constructor(message: string, public readonly scheduleId: string) {
    super(message);
  }
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
   *
   * @throws {@link ScheduleAlreadyRunning} if there's a running (not deleted) Schedule with the given `id`
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
   *
   * To list one page at a time, instead use the raw gRPC method {@link WorkflowService.listSchedules}:
   *
   * ```ts
   * await { schedules, nextPageToken } = client.scheduleService.listSchedules()
   * ```
   */
  public list(options?: ListScheduleOptions): AsyncIterator<ListScheduleEntry> {}

  /**
   * Get a handle to a Schedule
   *
   * This method does not validate `scheduleId`. If there is no Schedule with the given `scheduleId`, handle
   * methods like `handle.describe()` will throw a {@link ScheduleNotFoundError} error.
   */
  public getHandle(scheduleId: string): ScheduleHandle {  }
}
````

### Higher-level TS client

```ts
import { Client } from '@temporalio/client'

const client = new Client(options)

client.schedule.create()
client.workflow.start()
client.asyncCompletion.heartbeat()
client.operator.addSearchAttributes()

interface ClientOptions {
  dataConverter?: DataConverter
  interceptors?: {
    workflow: WorkflowClientInterceptors
    schedule: ScheduleClientInterceptors
  }
  identity?: string
  connection?: ConnectionLike
  namespace?: string
  queryRejectCondition?: temporal.api.enums.v1.QueryRejectCondition
}
```

### Interceptors

```ts
interface ScheduleClientCallsInterceptor {
  /**
   * Intercept a service call to CreateSchedule
   */
  create?: (
    input: ScheduleStartInput,
    next: Next<this, 'create'>
  ) => Promise<string /* conflictToken */>
}

interface ScheduleClientCallsInterceptorFactoryInput {
  id: string
}

/**
 * A function that takes a {@link ScheduleClientCallsInterceptorFactoryInput} and returns an interceptor
 */
export interface ScheduleClientCallsInterceptorFactory {
  (
    input: ScheduleClientCallsInterceptorFactoryInput
  ): ScheduleClientCallsInterceptor
}

/**
 * A mapping of interceptor type of a list of factory functions
 */
export interface ScheduleClientInterceptors {
  calls?: ScheduleClientCallsInterceptorFactory[]
}
```

- cron_string holds a traditional cron specification as a string. It
- accepts 5, 6, or 7 fields, separated by spaces, and interprets them the
- same way as CalendarSpec.
- 5 fields: minute, hour, day_of_month, month, day_of_week
- 6 fields: minute, hour, day_of_month, month, day_of_week, year
- 7 fields: second, minute, hour, day_of_month, month, day_of_week, year
- If year is not given, it defaults to \*. If second is not given, it
- defaults to 0.
- Shorthands @yearly, @monthly, @weekly, @daily, and @hourly are also
- accepted instead of the 5-7 time fields.
- Optionally, the string can be preceded by CRON_TZ=<timezone name> or
- TZ=<timezone name>, which will get copied to timezone_name. (There must
- not also be a timezone_name present.)
- Optionally "#" followed by a comment can appear at the end of the string.
- Note that the special case that some cron implementations have for
- treating day_of_month and day_of_week as "or" instead of "and" when both
- are set is not implemented.
- @every <interval>[/<phase>] is accepted and gets compiled into an
- IntervalSpec instead. <interval> and <phase> should be a decimal integer
- with a unit suffix s, m, h, or d.
