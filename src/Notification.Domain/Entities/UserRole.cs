using System;
using System.Collections.Generic;

namespace Notification.Domain.Entities;

public partial class UserRole
{
    public Guid UserId { get; set; }

    public int RoleId { get; set; }

    public Guid? AssignedBy { get; set; }

    public DateTime? AssignedAt { get; set; }

    public virtual User? AssignedByNavigation { get; set; }

    public virtual Role Role { get; set; } = null!;

    public virtual User User { get; set; } = null!;
}
