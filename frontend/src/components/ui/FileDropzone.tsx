import { useCallback, useState, type DragEvent } from 'react';
import { motion } from 'motion/react';
import { Upload } from 'lucide-react';
import { cn } from '../../lib/cn';

export function FileDropzone({
  onFile,
  onFiles,
  accept,
  multiple = false,
  className,
}: {
  onFile?: (file: File) => void;
  onFiles?: (files: File[]) => void;
  accept?: string;
  multiple?: boolean;
  className?: string;
}) {
  const [dragging, setDragging] = useState(false);

  const emit = useCallback(
    (list: FileList | null) => {
      const files = list ? Array.from(list) : [];
      if (files.length === 0) return;
      if (onFiles) onFiles(files);
      else if (onFile) onFile(files[0]);
    },
    [onFiles, onFile]
  );

  const onDrop = (e: DragEvent) => {
    e.preventDefault();
    setDragging(false);
    emit(e.dataTransfer.files);
  };

  return (
    <motion.label
      onDragOver={(e) => {
        e.preventDefault();
        setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={onDrop}
      animate={{
        borderColor: dragging ? 'hsl(160 84% 34%)' : 'hsl(138 21% 91%)',
        backgroundColor: dragging ? 'hsl(153 46% 91%)' : 'hsl(135 29% 97%)',
      }}
      transition={{ duration: 0.15 }}
      className={cn(
        'flex cursor-pointer flex-col items-center justify-center rounded-card border-2 border-dashed border-border bg-surface-muted px-6 py-12 text-center transition-colors',
        className
      )}
    >
      <input
        type="file"
        accept={accept}
        multiple={multiple}
        className="sr-only"
        onChange={(e) => emit(e.target.files)}
      />
      <motion.div
        animate={{ scale: dragging ? 1.05 : 1 }}
        className="mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-accent-muted"
      >
        <Upload className="h-6 w-6 text-accent" />
      </motion.div>
      <span className="text-sm font-medium text-text-primary">
        {multiple ? 'Drop files here or click to browse' : 'Drop a file here or click to browse'}
      </span>
      <span className="mt-1 text-xs text-text-secondary">
        PDF, DOCX, or images up to 10MB{multiple ? ' · select several at once' : ''}
      </span>
    </motion.label>
  );
}
