"use client";

export function ShimmerSkeleton({ className = "" }: { className?: string }) {
  return (
    <div className={`shimmer-bone ${className}`} />
  );
}

export function StatSkeleton() {
  return (
    <div className="panel p-4 sm:p-5">
      <ShimmerSkeleton className="h-3 w-20 rounded" />
      <ShimmerSkeleton className="mt-3 h-7 w-28 rounded" />
    </div>
  );
}

export function BoardSkeleton() {
  return (
    <div className="panel panel-sheen p-5 sm:p-6">
      <ShimmerSkeleton className="h-5 w-40 rounded" />
      <ShimmerSkeleton className="mt-2 h-3 w-56 rounded" />
      <div className="mt-6 flex justify-center">
        <ShimmerSkeleton className="h-48 w-full max-w-md rounded-xl" />
      </div>
    </div>
  );
}

export function StageSkeleton() {
  return (
    <div className="panel panel-sheen p-5 sm:p-6">
      <ShimmerSkeleton className="h-5 w-32 rounded" />
      <ShimmerSkeleton className="mt-2 h-3 w-48 rounded" />
      <div className="mt-5 space-y-2">
        {[0, 1, 2].map((i) => (
          <div key={i} className="flex items-center gap-3 rounded-xl border border-line bg-surface-2/60 p-4">
            <ShimmerSkeleton className="h-[52px] w-[52px] shrink-0 rounded-full" />
            <div className="flex-1">
              <ShimmerSkeleton className="h-4 w-20 rounded" />
              <ShimmerSkeleton className="mt-2 h-2.5 w-32 rounded" />
            </div>
            <ShimmerSkeleton className="h-4 w-16 rounded" />
          </div>
        ))}
      </div>
    </div>
  );
}

export function DashboardSkeleton() {
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 sm:gap-4">
        {[0, 1, 2, 3].map((i) => <StatSkeleton key={i} />)}
      </div>
      <BoardSkeleton />
      <StageSkeleton />
    </div>
  );
}
