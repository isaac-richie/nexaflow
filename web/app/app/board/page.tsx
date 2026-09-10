import { MemberDashboard } from "@/components/app/member-dashboard";
import { V6Member } from "@/components/app/v6-member";
import { IS_V6 } from "@/lib/contracts/config";

export default function BoardPage() {
  return IS_V6 ? <V6Member view="boards" /> : <MemberDashboard view="boards" />;
}
