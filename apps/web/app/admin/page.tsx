import AdminBoard from "@/components/AdminBoard";

// Moderation must never be cached or prerendered.
export const dynamic = "force-dynamic";

export const metadata = { robots: { index: false, follow: false } };

export default function AdminPage() {
  return <AdminBoard />;
}
